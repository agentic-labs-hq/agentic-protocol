# Indexing

Index from the deployment start block for chain 56. Addresses are in
[`../deployments/56.json`](../deployments/56.json).

This repository does not include a hosted indexer. Projects can index the events
below with their own infrastructure.

## Core events

### Token creation

`AgenticTokenFactory.TokenCreated`

```text
token   (address indexed)
creator (address indexed)
policy  (address indexed)
```

The token is an ERC-20; index standard `Transfer` events for balances.

### Pool creation

`AgentswapPoolFactory.GatedPoolCreated`

```text
pool          (address indexed)
token0        (address indexed)
token1        (address indexed)
fee           (uint24)
sqrtPriceX96  (uint160)
```

The pool is a Uniswap V3 pool. Index standard V3 `Swap`, `Mint`, `Burn`,
`Collect`, and `Flash` events from the pool address.

### Facility creation

`AgenticFacilityFactoryV2.FacilityCreated`

```text
facility (address indexed)
kind     (bytes32 indexed)
creator  (address indexed)
```

`kind` is `keccak256` of `VAULT`, `LAUNCH`, `LOCKER`, `GAME`, or `ESCROW`.
Read `facilityType()` and `owner()` from the facility after creation.

## Facility events

Common:

```text
OwnershipTransferStarted(current indexed, pending indexed)
OwnershipTransferred(previous indexed, newOwner indexed)
FacilityMigrated(replacement indexed)
```

CUSTODY:

```text
VAULT:    TokenReleased(token indexed, to indexed, amount), NativeReleased(to indexed, amount)
LAUNCH:   OperatorSet(operator indexed), BeneficiarySet(beneficiary indexed), Closed(), TokenReleased(...), NativeReleased(...)
LOCKER:   BeneficiarySet(beneficiary indexed), UnlockTimeExtended(...), Unlocked(...)
```

PURPOSE:

```text
GAME:    OperatorSet, Consumed(token indexed, amount), TokenReleased(...), TokenRefunded(...)
ESCROW:  ArbiterSet, BeneficiarySet, Deposited(token indexed, depositor indexed, amount), Released(...), Refunded(...)
```

Use the generated ABIs in [`../abi/`](../abi/) for exact indexed fields and the
full event list.

## State to read

- `AgenticAssetRegistry.isRegistered(token)`, `creatorOf(token)`,
  `policyOf(token)`.
- `AgenticVenueRegistry.isFacility(facility)`,
  `isFacilityOfCategory(facility, category)`.
- `AgentswapPoolFactory.isAllowedFee(fee)`, `treasury()`.
- `AgentswapPositionManager.positions(tokenId)`,
  `policyOfToken(token)`, `isAllowedRecipient(token, to)`.
- Facility role getters: `owner`, `operator`, `beneficiary`, `arbiter`,
  `depositor`, `unlockTime`, `hasDeposit`. V2 ESCROW has no `stateOf(token)`;
  settlement is balance-based.

## Reorg and finality

Use a confirmation depth appropriate for BSC. Store transaction hash, block
number, and log index; make indexing idempotent.

## Notes

- A facility creation and its registration happen atomically; index both the
  factory event and registry state.
- A pool creation and its registration happen atomically.
- `GatedPoolCreated` is the canonical pool-creation event; the underlying V3
  factory also emits `PoolCreated`, but use the wrapper event for gated-pool
  metadata.
