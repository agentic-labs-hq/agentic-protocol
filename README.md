# Agentic Protocol

Agent-ID-gated asset protocol and Agentswap, a gated DEX on BNB Smart Chain
(BSC, chain 56).

- Gated token standard and transfer policy
- Agent ID identity adapter and registries
- Standard facilities: VAULT / LAUNCH / LOCKER / GAME / ESCROW
- Gated NFT standard, NFT facilities, and Agentmarket
- Agentswap: Uniswap V3-based gated DEX with Agent-only pools and LP
- Builder documentation, ABIs, addresses, and verification material
- Live on BSC mainnet

This repository is the public integration source for the deployed contracts. It
contains no deployment credentials.

New to the protocol? Read [Background: Agent ID, Agentic Wallet, and protocol concepts](docs/BACKGROUND.md) first. It defines Agent ID, Binance Agentic Wallet, gated tokens, facilities, and who needs an Agent ID.

## Scope

- **Protocol contracts:** fixed-supply gated token, transfer policy and policy registry,
  identity adapter/registry, asset and quote registries, venue registry,
  protocol treasury, the Facility V2 builder stack (VAULT/LAUNCH/LOCKER/
  GAME/ESCROW), the gated NFT standard, NFT facilities, and Agentmarket.
- **Agentswap DEX:** Uniswap V3 fork with Agent-only pools and LP, gated position
  manager, router, quoter, protocol fee, and position descriptor.
- **Tests and reproducible build configuration** for the public contracts.

The repository contains the public contracts, tests, documentation, examples,
and address book.

## Layout

```text
contracts/          Protocol Solidity sources (solc 0.8.20)
dex/contracts/      Agentswap DEX sources (solc 0.7.6)
dex/lib/            pinned DEX dependencies
lib/                pinned protocol dependencies
test/               protocol tests
dex/test/           DEX tests
abi/                generated public ABIs
deployments/        public BSC address book
docs/               public integration docs
examples/           minimal TypeScript examples
```

## Documentation

- [Background and concepts](docs/BACKGROUND.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Minimal token-and-pool example](docs/QUICKSTART.md)
- [Token, pool, LP, and swap](docs/TOKEN_AND_POOL.md)
- [Facility integration](docs/FACILITY_GUIDE.md)
- [NFT and Agentmarket](docs/NFT_AND_AGENTMARKET.md)
- [Indexing](docs/INDEXING.md)
- [Verification and build](docs/VERIFICATION.md)

Using the terminal or an MCP client? See the [Agentswap CLI](https://github.com/agentic-labs-hq/agentswap-cli) for tokens and pools, or the [Agentmarket CLI](https://github.com/agentic-labs-hq/agentmarket-cli) for NFTs and listings.

## Choose your path

| Goal | Start here |
| --- | --- |
| Understand Agent ID, wallet, eligibility, and roles | [Background and concepts](docs/BACKGROUND.md) |
| Issue a token and create its first pool | [Minimal token-and-pool example](docs/QUICKSTART.md) |
| Add LP, quote, or swap | [TOKEN_AND_POOL.md](docs/TOKEN_AND_POOL.md) |
| Create a project facility | [FACILITY_GUIDE.md](docs/FACILITY_GUIDE.md) |
| Issue NFTs or sell them on Agentmarket | [NFT_AND_AGENTMARKET.md](docs/NFT_AND_AGENTMARKET.md) |
| Index events | [INDEXING.md](docs/INDEXING.md) |
| Use the CLI or MCP server | [Agentswap CLI](https://github.com/agentic-labs-hq/agentswap-cli) |

## Build

The build baseline uses Foundry 1.8.6. Compiler versions are pinned in the
Foundry configuration.

```sh
./scripts/build.sh
```

The script builds and tests the DEX first, checks the pool init-code hash, then
builds and tests the protocol contracts, and checks that the committed ABIs match
the build. The contracts use solc `0.8.20` (protocol) and `0.7.6` (DEX),
optimizer runs `200`, and the Paris EVM target where supported.

## Mainnet

Public BSC mainnet addresses are in [`deployments/56.json`](deployments/56.json).
The contracts are live; this repository does not redeploy them. The V2 facility
factory is the registered CUSTODY/PURPOSE builder path. NFT and Agentmarket
addresses are in the same book.

## Security

This repository contains no private keys, signer material, or deployment
credentials. Do not use it to deploy to mainnet without an independent
operational review.

See [`SECURITY.md`](SECURITY.md) for vulnerability reporting.

## License

- Original protocol contracts: MIT. See [`LICENSES/MIT.txt`](LICENSES/MIT.txt).
- DEX-derived contracts: GPL-2.0-or-later. See [`LICENSE`](LICENSE).
- Vendored dependencies retain their upstream licenses. See
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

The DEX is a fork of Uniswap V3. Uniswap is not affiliated with this project.
