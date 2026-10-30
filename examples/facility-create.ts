import {
  encodeAbiParameters,
  keccak256,
  parseAbi,
  toHex,
  type Address,
  type Hex,
  type WalletClient
} from "viem";

const facilityFactoryAbi = parseAbi([
  "function createFacility(bytes32 kind, bytes initData) returns (address)",
  "event FacilityCreated(address indexed facility, bytes32 indexed kind, address indexed creator)"
]);

export type CreateLaunchFacilityArgs = {
  facilityFactory: Address;
  owner: Address;
  operator: Address;
  /** Must be an Agent-ID-eligible agent. */
  beneficiary: Address;
};

/**
 * Creates a LAUNCH facility. The caller pays gas; `owner` is the project
 * owner. The beneficiary must be an eligible agent.
 *
 * Sign with your own wallet client. Never commit a private key.
 */
export async function createLaunchFacility(
  walletClient: WalletClient,
  args: CreateLaunchFacilityArgs
): Promise<Hex> {
  const kind = keccak256(toHex("LAUNCH"));

  const initData = encodeAbiParameters(
    [{ type: "address" }, { type: "address" }, { type: "address" }],
    [args.owner, args.operator, args.beneficiary]
  );

  return walletClient.writeContract({
    account: walletClient.account!,
    chain: walletClient.chain,
    address: args.facilityFactory,
    abi: facilityFactoryAbi,
    functionName: "createFacility",
    args: [kind, initData]
  });
}

/**
 * VAULT, LOCKER, GAME, and ESCROW use different `initData` tuples. LENDING
 * is not supported by Facility V2. See docs/FACILITY_GUIDE.md for exact
 * encodings and role requirements.
 */
export const kindLabels = {
  vault: "VAULT",
  launch: "LAUNCH",
  locker: "LOCKER",
  game: "GAME",
  escrow: "ESCROW"
} as const;

export function kindOf(label: keyof typeof kindLabels): Hex {
  return keccak256(toHex(kindLabels[label]));
}
