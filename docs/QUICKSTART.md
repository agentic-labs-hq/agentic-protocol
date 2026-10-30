# Minimal token-and-pool example

This is the shortest useful integration path: create a fixed-supply gated token,
wait for the receipt, read the new token address from the `TokenCreated` event,
and create its first gated pool against USDT.

It is not a complete trading or LP tutorial. LP, swap, facility, and indexing are
separate tasks; links are at the end.

New to Agent ID or Binance Agentic Wallet? Read
[Background and concepts](BACKGROUND.md) first.

## What you need

- A BSC RPC endpoint and a viem wallet client with BNB for gas.
- The recipient of the initial supply must be an eligible Agent ID wallet.
- Addresses from [`../deployments/56.json`](../deployments/56.json).
- The ABIs from [`../abi/`](../abi/), or the small ABI definitions below.

The token creator does **not** need an Agent ID. The initial recipient does.
Pool creation is caller-authorized: the caller must be the creator of every
gated side.

## Code

```ts
import {
  createPublicClient,
  createWalletClient,
  http,
  parseAbi,
  type Address,
  type Hex,
} from "viem";

const tokenFactoryAbi = parseAbi([
  "event TokenCreated(address indexed token, address indexed creator, address indexed policy)",
  "function createToken(string name, string symbol, address policy, address[] initialRecipients, uint256[] initialAmounts, string metadataURI) returns (address)",
]);

const poolFactoryAbi = parseAbi([
  "event GatedPoolCreated(address indexed pool, address indexed token0, address indexed token1, uint24 fee, uint160 sqrtPriceX96)",
  "function createPool(address tokenA, address tokenB, uint24 fee, uint160 sqrtPriceX96) returns (address)",
]);

const addresses = {
  tokenFactory: "0x0c05551Ba2d262e99616634111ef693716A986ce" as Address,
  poolFactory: "0xEc281F077C643CaDd4Ca90724C287552ca3e84e7" as Address,
  usdt: "0x55d398326f99059fF775485246999027B3197955" as Address,
};

const publicClient = createPublicClient({ transport: http(process.env.BSC_RPC_URL) });

// `wallet` is your own viem WalletClient; never commit its key.
// `agentRecipient` must be an eligible Agent ID wallet.
async function createTokenAndPool(
  wallet: ReturnType<typeof createWalletClient>,
  agentRecipient: Address,
): Promise<{ token: Address; pool: Address }> {
  const tokenHash: Hex = await wallet.writeContract({
    account: wallet.account!,
    chain: wallet.chain,
    address: addresses.tokenFactory,
    abi: tokenFactoryAbi,
    functionName: "createToken",
    args: [
      "Example Agent Token",
      "EGT",
      "0x0000000000000000000000000000000000000000",
      [agentRecipient],
      [1_000_000n * 10n ** 18n],
      "ipfs://example/token.json",
    ],
  });

  const tokenReceipt = await publicClient.waitForTransactionReceipt({ hash: tokenHash });
  const [created] = await publicClient.getContractEvents({
    address: addresses.tokenFactory,
    abi: tokenFactoryAbi,
    eventName: "TokenCreated",
    fromBlock: tokenReceipt.blockNumber,
    toBlock: tokenReceipt.blockNumber,
  });
  if (!created?.args.token) throw new Error("TokenCreated event not found");

  // Any valid initial price can be used. This example uses 1:1 only as a
  // placeholder; adjust for the two tokens' decimals and the intended price.
  const sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336n; // 2^96

  const poolHash: Hex = await wallet.writeContract({
    account: wallet.account!,
    chain: wallet.chain,
    address: addresses.poolFactory,
    abi: poolFactoryAbi,
    functionName: "createPool",
    args: [created.args.token, addresses.usdt, 3000, sqrtPriceX96],
  });

  const poolReceipt = await publicClient.waitForTransactionReceipt({ hash: poolHash });
  const [poolCreated] = await publicClient.getContractEvents({
    address: addresses.poolFactory,
    abi: poolFactoryAbi,
    eventName: "GatedPoolCreated",
    fromBlock: poolReceipt.blockNumber,
    toBlock: poolReceipt.blockNumber,
  });
  if (!poolCreated?.args.pool) throw new Error("GatedPoolCreated event not found");

  return { token: created.args.token, pool: poolCreated.args.pool };
}
```

## What the call does

1. `createToken` mints the total supply to `agentRecipient` and fixes it forever.
   The caller becomes the token creator.
2. `createPool` creates and initializes the gated USDT pool, assigns the protocol
   fee, and registers the pool as a `POOL` facility.
3. The emitted events are the reliable way to get the new token and pool
   addresses. A transaction hash alone does not return the created address.

The example deliberately omits the `policy` address by passing `address(0)`,
which selects the current approved policy.

## What you have now

You have a token and an initialized pool. You do **not** yet have a tradable
market: a pool with no liquidity has no swaps. The next steps are separate
tasks, not optional features of the token/pool transaction:

- **Add liquidity** to make the pool usable.
- **Quote/swap** after liquidity exists.

- **Add agent liquidity:** [TOKEN_AND_POOL.md §3](TOKEN_AND_POOL.md#3-provide-liquidity).
- **Quote and swap:** [TOKEN_AND_POOL.md §4](TOKEN_AND_POOL.md#4-quote-and-swap).
- **Create a project facility:** [FACILITY_GUIDE.md](FACILITY_GUIDE.md). This is
  a separate project task and is not required for a token or pool.
- **Index events:** [INDEXING.md](INDEXING.md).
- **Run the CLI instead of writing TypeScript:** see the
  [Agentswap CLI](https://github.com/agentic-labs-hq/agentswap-cli).

For the full token/pool rules and the fee-tier list, see
[TOKEN_AND_POOL.md](TOKEN_AND_POOL.md). For build verification, see
[VERIFICATION.md](VERIFICATION.md).
