import {
  parseAbi,
  type Address,
  type Hex,
  type WalletClient
} from "viem";

const tokenFactoryAbi = parseAbi([
  "function createToken(string name, string symbol, address policy, address[] initialRecipients, uint256[] initialAmounts, string metadataURI) returns (address)"
]);

const poolFactoryAbi = parseAbi([
  "function createPool(address tokenA, address tokenB, uint24 fee, uint160 sqrtPriceX96) returns (address)"
]);

export type CreateGatedTokenArgs = {
  tokenFactory: Address;
  name: string;
  symbol: string;
  /** address(0) selects the current approved policy. */
  policy: Address;
  initialRecipients: Address[];
  initialAmounts: bigint[];
  metadataURI: string;
};

export type CreateGatedPoolArgs = {
  poolFactory: Address;
  tokenA: Address;
  tokenB: Address;
  /** Enabled V3 fee tier, for example 3000. */
  fee: number;
  sqrtPriceX96: bigint;
};

/** The caller becomes the token creator and needs no Agent ID. */
export async function createGatedToken(
  walletClient: WalletClient,
  args: CreateGatedTokenArgs
): Promise<Hex> {
  return walletClient.writeContract({
    account: walletClient.account!,
    chain: walletClient.chain,
    address: args.tokenFactory,
    abi: tokenFactoryAbi,
    functionName: "createToken",
    args: [
      args.name,
      args.symbol,
      args.policy,
      args.initialRecipients,
      args.initialAmounts,
      args.metadataURI
    ]
  });
}

/**
 * The caller must be the creator of every gated token in the pair, and at
 * least one side must be a registered gated asset. The other side must be
 * gated or an approved quote asset.
 */
export async function createGatedPool(
  walletClient: WalletClient,
  args: CreateGatedPoolArgs
): Promise<Hex> {
  return walletClient.writeContract({
    account: walletClient.account!,
    chain: walletClient.chain,
    address: args.poolFactory,
    abi: poolFactoryAbi,
    functionName: "createPool",
    args: [args.tokenA, args.tokenB, args.fee, args.sqrtPriceX96]
  });
}

/**
 * The pool must exist before an agent can mint an LP position through
 * AgentswapPositionManager. Quote token policy is skipped; gated/gated checks
 * both token policies.
 */
export const notes = [
  "Use an eligible Agent ID wallet for gated swaps and LP.",
  "Compute sqrtPriceX96 from the intended initial price before pool creation.",
  "Approve tokens explicitly before LP mint or swap."
] as const;
