# Verification and reproducible build

This page records the public build settings and the limits of what this
repository proves. It does not by itself certify the deployed bytecode.

Three different checks are often called "verified"; this page keeps them
separate:

- **Build baseline:** this repository builds and tests from pinned settings.
- **BscScan source verification:** the explorer has a source record for a
  deployed address.
- **Runtime bytecode comparison:** the deployed code is compared with a compiled
  artifact, accounting for metadata.

## Compiler settings

| Project | Solidity | Optimizer | EVM target | Source |
| --- | --- | --- | --- | --- |
| Protocol | `0.8.20` | `200` runs | `paris` | `contracts/` |
| DEX | `0.7.6` | `200` runs | resolves to Istanbul for this compiler | `dex/contracts/` |
| DEX libraries | `0.7.6` | `200` runs | same | `dex/lib/` |

Settings are pinned in [`../foundry.toml`](../foundry.toml) and
[`../dex/foundry.toml`](../dex/foundry.toml).

## Build from a clean clone

```sh
cd dex
forge build
forge test

cd ..
node scripts/check-pool-hash.mjs
forge build
forge test

node scripts/generate-abis.mjs --check
```

The protocol cross-version tests read the DEX build artifacts from `dex/out`; build
the DEX first.

## Pool init-code hash

`PoolAddress.POOL_INIT_CODE_HASH` is:

```text
0xb2635d2e91d517bfbbcc2804c6a779c0f78ca6ee09d8d3f7ba48f1a5c35e5f9e
```

This is the Keccak-256 hash of the compiled `UniswapV3Pool` creation code. The
DEX tests include a real-core address/hash check.

## Deployed records

Public mainnet addresses are in [`../deployments/56.json`](../deployments/56.json).
The legacy deployment records and the Facility V2 factory/helper have BscScan
source verification. Use the explorer's source and compiler settings as the
deployed-instance record:

- Factory: https://bscscan.com/address/0xf9E9A9F98e012C01994B91D83b57278ED08d4534#code
- Helper: https://bscscan.com/address/0x461d62f74D1Da990643F99A39B2b1052B4008d72#code


The deployed `AgentswapV3Factory` was compiled from a source with the upstream
`BUSL-1.1` header. This public tree uses the GPL-2.0-or-later header. The change
is comment-only; the executable runtime is identical after stripping the
Solidity metadata, but the metadata hash differs. This is documented in
[`../THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md). Compare runtime code
with metadata stripped when checking that specific contract.

## Reproducibility notes

- The vendored dependency source subset and explicit remappings are part of the
  build input. Do not remove or reorder them without re-checking the pool
  init-code hash and ABI output.
- `scripts/generate-abis.mjs --check` fails if committed ABIs are stale.
- Build artifacts (`out/`, `cache/`) are not committed.
- The repository does not include deployment scripts, keys, applications,
  backends, or private test material.

## Security

See [SECURITY.md](../SECURITY.md) for vulnerability reporting and security
contact information. Review the deployed addresses and documented integration
constraints before integrating.
