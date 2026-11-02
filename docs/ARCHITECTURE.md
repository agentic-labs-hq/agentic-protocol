# Architecture

Agentic Protocol is a token protocol for Agent ID-gated assets, with Agentswap
as its first DEX venue. This document covers the public contracts only.

For definitions of Agent ID, Binance Agentic Wallet, eligibility, and the roles
used below, read [Background and concepts](BACKGROUND.md).

## Layers

```text
Protocol layer
    token protocol
    fixed-supply gated token
    versioned transfer policy + policy registry
    identity adapter / identity registry
    asset registry, quote-asset registry, venue registry
    facility factory + standard CUSTODY/PURPOSE templates
    protocol treasury

Agentswap DEX
    gated Uniswap V3 pool factory
    Agent-only position manager
    router, quoter, position descriptor
```

The token policy checks **categories**, not specific DEX addresses:
`POOL`, `LP_MANAGER`, `FEE_RECIPIENT`, `CUSTODY`, and `PURPOSE`. A future DEX or
venue can register under the existing categories after a governance decision.

## Token

- `AgenticToken` is an ERC-20 with a fixed supply.
- Tokens are deployed by `AgenticTokenFactory`; direct deployment is not a
  protocol asset.
- The initial supply is minted to one or more eligible recipients: agents or
  active CUSTODY/PURPOSE facilities.
- The token's policy is immutable for that token.
- There is no admin mint, pause, upgrade, or arbitrary transfer path.

## Identity and policy

- `AgenticIdAdapter` is the first identity adapter; it reads the external Agent
  ID registry.
- `AgenticIdentityRegistry` stores active adapters.
- `AgenticPolicy` is the category matrix for policy version 1.
- `AgenticPolicyRegistry` manages allowed policy versions.
- Existing tokens keep their policy version. A new policy version is for new
  tokens.

## Registries

- `AgenticAssetRegistry` records gated tokens and their creator/policy.
- `AgenticQuoteAssetRegistry` manages approved quote assets.
- `AgenticVenueRegistry` records facility categories/subtypes and active
  facilities.
- Registry administration is executed by the 2-of-3 Safe immediately; there is no active timelock. Transferring the governance address itself uses a two-step propose/accept process.

## Facilities

The word "facility" has two scopes:

- **Registry facility:** any registered venue, including `POOL` and
  `LP_MANAGER`.
- **Project facility:** a standard contract that can hold gated tokens without
  an Agent ID and expose a fixed role/lifecycle surface. The V2 project
  templates are `VAULT`, `LAUNCH`, `LOCKER`, `GAME`, and `ESCROW`.

The policy sees the facility **category**; project builders choose a **kind**
(template). `CUSTODY` (`VAULT`, `LAUNCH`, `LOCKER`) pays gated tokens only to
agents. `PURPOSE` (`GAME`, `ESCROW`) provides agent-to-purpose and
purpose-to-agent utility flows.

Facilities are created permissionlessly through `AgenticFacilityFactoryV2`.
The factory supports `VAULT`, `LAUNCH`, `LOCKER`, `GAME`, and `ESCROW`; it
checks a canonical codehash, so proxies and arbitrary implementations are
rejected. See [FACILITY_GUIDE.md](FACILITY_GUIDE.md).

## Agentswap DEX

- Uniswap V3 core math is unchanged.
- `AgentswapPoolFactory` is the only creator of canonical V3 pools. At least one
  side must be a registered gated asset; the other must be gated or an approved
  quote asset.
- Pool creation is creator-authorized: the caller must be the creator of every
  gated side.
- Gated pools are Agent-only for swaps and LP.
- `AgentswapPositionManager` enforces the token policy for position ownership,
  transfers, operations, and collection recipients.
- Protocol fee is currently `1/8` of the LP swap fee on each side, collected to
  `AgenticTreasury`. It is not 1/8 of trade notional: in a 0.30% pool the
  protocol receives 0.0375% of notional and LPs keep 0.2625%.
- `AgentswapQuoter` is read-only. Its simulated recipient is the caller so
  gated-output quotes reflect the real agent recipient.

## Trust boundaries

- Contract governance is controlled by a 2-of-3 Safe. Administrative actions execute immediately; no timelock is active. The two-step mechanism applies only to transferring the governance address.
- Permissionless token and facility creation has no per-project review.
- Project facility owners are responsible for their own roles and operations.
- The protocol does not custody project sale proceeds or app-level funds.

## Current limitations and integration impact

These are current behavior, not hidden exceptions:

- **Raw pool mint bypasses the position manager.** The token policy still blocks
  non-agent recipients, but the position manager's full LP-user checks do not
  run. Use `AgentswapPositionManager` for normal LP.
- **Gated protocol fees accumulate in the treasury before conversion.** An
  eligible-agent operator (manual or automated) moves them out; this is not an
  atomic user-facing operation. Public assets are transferred by governance and
  converted externally, so the deployed public-asset swap path is not a
  supported product feature.
- **No LP locker and no facility LP positions in the current deployment.** A
  project that wants market making must use an agent market maker that owns the
  LP position.
- **Facility V2 ESCROW is balance-based.** Partial release/refund is allowed;
  once a token starts release or refund, the remaining balance stays in that
  direction. A fully settled token rejects new deposits. It cannot recover v1
  balances already locked.

## Not in this repository

Application UIs, backends, indexers, deployment automation, and other
repositories are separate and are not part of this public source package.
