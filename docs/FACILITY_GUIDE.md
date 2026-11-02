# Facility integration guide

Facilities are standard on-chain contracts used by projects. They can hold
gated tokens without an Agent ID and expose a fixed role/lifecycle surface.

The word **facility** has a broad and a narrow meaning:

- **Registry facility:** any contract registered in the venue registry, including
  `POOL` and `LP_MANAGER`.
- **Project facility:** one of the five Facility V2 templates covered here:
  `VAULT`, `LAUNCH`, `LOCKER`, `GAME`, `ESCROW`.

For the full category/kind/venue distinction, read
[Background and concepts](BACKGROUND.md#facility-broad-and-narrow-meanings).

## Choose a template first

| Kind | Use it for | How gated tokens can enter | Who can receive gated tokens from it | Not included |
| --- | --- | --- | --- | --- |
| `VAULT` | Project treasury with owner-controlled releases | Initial mint only; CUSTODY rejects incoming transfers | Owner releases to an eligible agent | No project/agent top-up path |
| `LAUNCH` | Primary-sale token custody | Initial mint only | Operator releases to an agent buyer; after close, to the beneficiary | Does not process sale proceeds |
| `LOCKER` | Time-locked gated allocation | Initial mint only | Fixed agent beneficiary after unlock | Not an LP locker |
| `GAME` | Game/utility sink | Initial mint, or a direct transfer from an eligible agent | Operator releases/refunds to an agent | No public deposit function |
| `ESCROW` | Two-party trade escrow with release/refund | `deposit()` from the eligible depositor, or a direct transfer | Agent beneficiary/depositor, according to release/refund direction | Not trustless vesting |

Before choosing, check the roles and per-kind restrictions in this guide. The
template names are not generic DeFi primitives: `VAULT` is not a
deposit-for-anyone vault, and `LOCKER` does not lock LP NFTs. The policy allows
a gated transfer from an agent only to a `POOL` or `PURPOSE` facility, so
`CUSTODY` templates cannot be topped up by an agent; a non-agent EOA also cannot
send gated tokens to any facility.

This guide covers the **Facility V2 builder path**:

- Factory: `deployments/56.json → contracts.agenticFacilityFactory`
- V2 ESCROW helper: `deployments/56.json → contracts.agenticEscrowV2TemplateDeployer`
- Registry: `deployments/56.json → contracts.agenticVenueRegistry`
- Factory ABI: [`../abi/AgenticFacilityFactoryV2.json`](../abi/AgenticFacilityFactoryV2.json)
- ESCROW ABI: [`../abi/AgenticEscrowFacilityV2.json`](../abi/AgenticEscrowFacilityV2.json)

Facility V2 supports `VAULT`, `LAUNCH`, `LOCKER`, `GAME`, and `ESCROW`; use the
V2 factory for every new facility.

## 1. Create a facility

```solidity
createFacility(bytes32 kind, bytes initData) returns (address facility)
```

- Permissionless; no per-project review.
- The factory deploys only the canonical template for `kind`.
- It verifies the deployed runtime codehash, registers the facility as
  `CUSTODY` or `PURPOSE`, and emits
  `FacilityCreated(facility, kind, creator)`.
- The caller is the event creator; the facility **owner** comes from
  `initData`.
- The facility owner does not need an Agent ID. Agent-only roles and every gated
  recipient are checked separately.
- `isSupportedType(kind)` and `codehashOf(kind)` are read-only checks.

### Kind constants

The `kind` argument is a `bytes32` label:

```text
VAULT  = keccak256("VAULT")
LAUNCH = keccak256("LAUNCH")
LOCKER = keccak256("LOCKER")
GAME   = keccak256("GAME")
ESCROW = keccak256("ESCROW")
```

### `initData` encodings

Use `abi.encode`, not packed encoding.

| Kind | `initData` |
| --- | --- |
| `VAULT` | `abi.encode(address owner)` |
| `LAUNCH` | `abi.encode(address owner, address operator, address beneficiary)` |
| `LOCKER` | `abi.encode(address owner, address beneficiary, uint64 unlockTime)` |
| `GAME` | `abi.encode(address owner, address operator)` |
| `ESCROW` | `abi.encode(address owner, address arbiter, address beneficiary, address depositor)` |

Agent-only roles are validated at creation and whenever set later. In
particular:

- `LAUNCH.beneficiary` is optional at creation but must be zero or an agent; it must be set to an agent before `close()`.
- `LOCKER.beneficiary` must be non-zero and an agent.
- `ESCROW.beneficiary` and `ESCROW.depositor` must be non-zero and agents.
- `ESCROW.arbiter` may be zero, but a non-zero arbiter is recommended.

## 2. Roles and lifecycle

### Common

- Owner: project EOA/multisig, no Agent ID.
- Ownership transfer is two-step: `transferOwnership` then `acceptOwnership`.
- Gated flows always go to an agent; public native/ERC-20 flows are separate.
- No arbitrary `call`, `delegatecall`, proxy, or pause.
- `migrate(replacement)` is available only after the facility is revoked; the
  replacement must be the registry replacement of the same category and
  subtype. Governance can revoke but cannot redirect a project replacement.
- Before any migration, verify the target factory, codehash, roles, and a full
  target outflow.
- Functions not listed for a subtype revert. Some inherited functions are
  intentionally reverting stubs (for example `LOCKER.release`,
  `GAME.liquidate`, `ESCROW.consume`); do not call them.

### CUSTODY

| Kind | Key functions | Rule |
| --- | --- | --- |
| `VAULT` | `release(token,to,amount)` | owner-only; gated; `to` must be an agent |
| `VAULT` | `releaseNative(to,amount)` | owner-only; public native |
| `LAUNCH` | `setOperator`, `setBeneficiary` | owner-only; operator non-zero; beneficiary agent-only |
| `LAUNCH` | `release(token,to,amount)` | operator-only; gated; agent buyer |
| `LAUNCH` | `close()` | owner or operator; marks the sale closed; subsequent gated releases go only to the beneficiary (agent) |
| `LOCKER` | `unlock(token,to,amount)` | anyone after `unlockTime`; `to` must equal the fixed beneficiary |
| `LOCKER` | `extend(uint64)` | owner-only before maturity; only increases |
| `LOCKER` | `setBeneficiary` | owner-only before unlock; agent-only |

`LAUNCH` payments are external to the facility. The contract releases tokens; it
does not process sale proceeds. Unsold gated tokens cannot return to a facility.

### PURPOSE

| Kind | Key functions | Rule |
| --- | --- | --- |
| `GAME` | `setOperator` | owner-only |
| `GAME` | `consume`, `release`, `refund` | operator-only; consume locks/consumes without changing supply; release/refund to agents |
| `ESCROW` | `setArbiter`, `setBeneficiary` (before funding), `deposit`, `release`, `refund` | beneficiary/arbiter release; depositor/arbiter refund; recipients agents |

`GAME` and `ESCROW` are utility sinks; they do not provide project withdrawal or
public release paths. `GAME` has no `deposit()` function: an eligible agent can
send gated tokens directly to it, and the operator consumes/releases/refunds.
`ESCROW` has a `deposit()` function, and direct transfers are also accepted and
spendable as part of its balance-based accounting.

#### ESCROW V2 settlement

V2 ESCROW is **balance-based**; it does not use a terminal
`NONE/FUNDED/RELEASED/REFUNDED` state.

- `release` and `refund` accept any `amount > 0` up to the current balance.
- Partial settlement is allowed. Once a token starts `RELEASE` or `REFUND`, the
  remaining balance stays in that direction; release and refund cannot be
  mixed for the same token in the same escrow.
- Direct mint/transfer and migration receipt are spendable without a synthetic
  `deposit` call.
- A fully settled token rejects new `deposit` calls (`EscrowAlreadySettled`).
  Use a new escrow instance for a new trade.
- Direct ERC-20 transfers after settlement cannot be rejected by the contract;
  the new balance follows the stored direction. Do not reuse a settled escrow
  for a new trade.
- The first `deposit` or successful settlement freezes the beneficiary for that
  normal path. The owner can change the beneficiary before then; this is a
  role-controlled escrow, not trustless vesting.
- The factory requires non-zero agent beneficiary and depositor at creation,
  which prevents a third party from becoming depositor with a dust deposit.

## 3. Events

Factory:

```text
FacilityCreated(address indexed facility, bytes32 indexed kind, address indexed creator)
```

Facility events include:

```text
OwnershipTransferStarted, OwnershipTransferred
TokenReleased, NativeReleased
OperatorSet, BeneficiarySet, ArbiterSet
Consumed, Deposited, Released, Refunded
Unlocked, UnlockTimeExtended, Closed, FacilityMigrated
```

Use the generated ABIs under [`../abi/`](../abi/) for exact indexed fields.

## 4. Minimal TypeScript example

See [`../examples/facility-create.ts`](../examples/facility-create.ts).

```text
kind = keccak256(toHex("VAULT"))
initData = encodeAbiParameters([{type:"address"}], [owner])
facilityFactory.createFacility(kind, initData)
```

The example does not include a private key. Sign with your own wallet.

## 5. Important constraints

- The facility's gated transfers still pass the token policy. Facility creation
  does not bypass token eligibility.
- `CUSTODY` cannot receive from an agent; it pays out to agents.
- `PURPOSE` flows are agent-to-purpose and purpose-to-agent only.
- There is no facility-to-facility gated transfer.
- No facility LP and no LP-NFT custody in the current deployment.
- Project owners are responsible for their own role assignment and operations.
