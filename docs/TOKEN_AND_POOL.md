# Token, pool, LP, and swap

All write calls are normal signed BSC transactions. This repository does not
contain private keys or a signer. Use your own wallet/client and review every
transaction before sending it.

Addresses: [`../deployments/56.json`](../deployments/56.json). ABIs:
[`../abi/`](../abi/).

For Agent ID, Binance Agentic Wallet, and role definitions, read
[Background and concepts](BACKGROUND.md) first.

## Roles at a glance

| Role | Agent ID required for this role? | Role grants holding? | Notes |
| --- | --- | --- | --- |
| Token creator | No | No | The caller becomes the creator; eligibility is separate. |
| Initial recipient | Yes, or active CUSTODY/PURPOSE facility | Yes | Checked at creation. |
| Pool creator | No | No | Must be creator of every gated side. |
| LP owner | Yes | Yes | Position owner and recipients are checked. |
| Swapper | Yes | Yes | Gated output to an eligible agent. |
| Facility owner | No | No | Project role; see facility guide. |

Roles can overlap: an eligible creator can also be a recipient or LP owner.
The table is a routing aid; the per-function rules below are authoritative.

## 1. Create a gated token

Call `AgenticTokenFactory.createToken` on
`deployments/56.json → contracts.agenticTokenFactory`.

```solidity
createToken(
    string name,
    string symbol,
    address policy,
    address[] initialRecipients,
    uint256[] initialAmounts,
    string metadataURI
) returns (address token)
```

Rules:

- `policy == address(0)` selects the current policy version.
- The total initial supply is the sum of `initialAmounts`; it is fixed at
  creation.
- Each initial recipient must be an Agent-ID-eligible agent or an active
  `CUSTODY`/`PURPOSE` facility. `POOL`, `LP_MANAGER`, and `FEE_RECIPIENT`
  recipients are rejected.
- Recipients must be unique.
- The caller becomes the token creator. No Agent ID is required for the caller.
- The token has no admin mint, pause, or upgrade path.

`TokenCreated(token, creator, policy)` is emitted by the factory.

## 2. Create a gated pool

Call `AgentswapPoolFactory.createPool` on
`deployments/56.json → contracts.agentswapPoolFactory`.

```solidity
createPool(
    address tokenA,
    address tokenB,
    uint24 fee,
    uint160 sqrtPriceX96
) returns (address pool)
```

Rules:

- At least one token must be a registered gated asset.
- Every non-gated token must be an approved quote asset (WBNB or USDT on this
  deployment).
- The caller must be the creator of every gated token in the pair.
- The enabled fee tiers are the canonical V3 factory's tiers; on this deployment
  they are `100` (0.01%), `500` (0.05%), `3000` (0.30%), and `10000` (1.00%).
- The pool is created with protocol fee `1/8` of the LP swap fee on each side.
  For a 0.30% pool, the protocol receives 0.0375% of swap notional and LPs keep
  the remaining 0.2625%; it is not 1/8 of the trade notional.
- `sqrtPriceX96` must be inside the V3 valid range and above zero.
- The pool is created, initialized at `sqrtPriceX96`, assigned protocol fee
  `(8,8)`, and registered as a `POOL` facility atomically.
- The project can create the pool but cannot LP or swap gated assets unless it
  controls an eligible agent wallet.

`GatedPoolCreated(pool, token0, token1, fee, sqrtPriceX96)` is emitted.

## 3. Provide liquidity

Use `AgentswapPositionManager` at
`deployments/56.json → contracts.agentswapPositionManager`.

- LP is Agent-only. Position owner, recipient, caller, and collect recipient are
  checked against the token policy.
- For a gated/gated pool, both tokens' policies are checked.
- The position is an ERC-721. The position manager enforces the policy on
  transfers and position operations.
- A project that wants market making must use an agent market maker: an
  operator controlling an eligible Agent ID wallet, which may be manual or
  automated. The LP NFT belongs to that agent.
- There is no facility LP and no LP locker in the current deployment.

Relevant calls: `mint`, `increaseLiquidity`, `decreaseLiquidity`, `collect`,
`burn`, and the ERC-721 transfer/approval methods. Use the
[`AgentswapPositionManager` ABI](../abi/AgentswapPositionManager.json).

### Minimal LP sequence

1. Decide the sorted `token0`/`token1`, fee tier, and a tick range aligned to the
   pool's tick spacing.
2. From the agent wallet, approve each gated token to the position manager for
   at least the desired amount.
3. Call `mint` with:

   ```text
   token0, token1, fee, tickLower, tickUpper,
   amount0Desired, amount1Desired,
   amount0Min, amount1Min,
   recipient, deadline
   ```

   `recipient` and every collect recipient must be eligible agents. The returned
   `tokenId` is the position NFT id; the call also returns the actual liquidity
   and used amounts.
4. If the transaction succeeds, the position exists. Use `positions(tokenId)` to
   read liquidity, ticks, and owed tokens before increasing, decreasing, or
   collecting.
5. For partial removal, use `decreaseLiquidity` with the liquidity amount and
   raw minima, then `collect`; only burn when liquidity and both owed balances
   are zero.

The interface is the exact ABI linked above. This section is the minimal
sequence, not a full position-management tutorial; the CLI wraps the same flow
with previews and explicit confirmation.

## 4. Quote and swap

- `AgentswapQuoter` is read-only. Use it to obtain expected amounts.
- `AgentswapRouter` performs exact-input swaps. Gated output can only go to an
  eligible agent (or the protocol fee recipient for protocol fees).
- A non-agent may supply public quote assets to a gated pool, but cannot receive
  or hold gated output.
- Approvals must be made explicitly; the router does not silently approve.
- For a single-pool exact-input swap, quote first, approve the input token to the
  router, then call `exactInputSingle` with `tokenIn`, `tokenOut`, `fee`,
  `recipient`, `deadline`, `amountIn`, `amountOutMinimum`, and
  `sqrtPriceLimitX96`. `recipient` must be an eligible agent for gated output.
  `amountOutMinimum` is the slippage guard; do not set it to zero casually.

A raw `pool.mint` position bypasses the position manager. The token policy still
blocks non-agent recipients, but it does not provide the position manager's full
LP-user checks. For normal LP use, go through `AgentswapPositionManager`.

## Flow overview

```text
create token (recipients = agents / active facilities)
→ create pool (caller = creator of every gated side)
→ add agent liquidity (separate task)
→ quote / swap (requires liquidity)
```

A token and pool alone do not form a tradable market. LP and swap are separate
tasks; without liquidity, the pool has no swaps. Facility and indexing are also
separate project paths.

See [`../examples/token-and-pool.ts`](../examples/token-and-pool.ts) for a
TypeScript skeleton. Replace all placeholder addresses and amounts.
