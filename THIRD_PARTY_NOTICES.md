# Third-party notices

This file records the upstream dependencies and license terms for the public
contracts. It is an engineering notice, not legal advice.

## Project license scope

- Original protocol contracts are licensed under MIT; see `LICENSES/MIT.txt`.
- DEX-derived contracts are licensed under GPL-2.0-or-later; see `LICENSE`.
- Vendored dependencies remain under their upstream licenses.

## Vendored dependencies

| Component | Pin | License | Public path |
| --- | --- | --- | --- |
| forge-std | `v1.9.7`, commit `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | MIT OR Apache-2.0 | `lib/forge-std/src` |
| OpenZeppelin Contracts | `v5.4.0`, commit `c64a1edb67b6e3f4a15cca8909c9482ad33a02b0` | MIT | `lib/openzeppelin-contracts/contracts` |
| Uniswap V3 Core | `v1.0.0`, commit `e3589b192d0be27e100cd0daaf6c97204fdb1899` | BUSL-1.1; Change Date 2023-04-01; Change License GPL-2.0-or-later | `dex/lib/v3-core/contracts` |
| Uniswap V3 Periphery | `v1.0.0`, commit `464a8a49611272f7349c970e0fadb7ec1d3c1086` | GPL-2.0-or-later | `dex/lib/v3-periphery/contracts`; fork target `dex/contracts` |
| OpenZeppelin Contracts | `v3.4.2-solc-0.7`, commit `04695aecbd4d17dddfd55de766d10e3805d6f42f` | MIT | `dex/lib/openzeppelin-contracts/contracts` |
| Uniswap V2 Core | `v1.0.1`, commit `4dd59067c76dea4a0e8e4bfdda41877a6b16dedc` | GPL-3.0 | `dex/lib/v2-core/contracts` |
| @uniswap/lib | `4.0.1-alpha`, `gitHead` `c01640b0f0f1d8a85cba8de378cc48469fcfd9a6` | GPL-3.0-or-later | `dex/lib/uniswap-lib/contracts` |
| base64-sol | `1.0.1`, `gitHead` `6ffe5810d64432fe5ed0f8664586115cf082c468` | MIT | `dex/lib/base64-sol/base64.sol` |

Upstream license files are retained in the vendored paths.

### Per-file SPDX exception

Two upstream V3 periphery files retain their upstream `UNLICENSED` SPDX header
even though the upstream package declares GPL-2.0-or-later. This repository does
not relicense them; the upstream file header and package-level license evidence
are retained. Downstream users should review the pinned upstream source and the
file-level notices.

## DEX modifications

The DEX is a fork of Uniswap V3. AMM math is unchanged. The fork changes are:

- `dex/contracts/AgentswapPositionManager.sol`: Agent-only LP gate with
  per-token policy resolution, recipient/transfer checks, and caller checks.
- `dex/contracts/factories/AgentswapV3Factory.sol`: pool creation restricted to
  the owning pool factory; pool bytecode and math unchanged.
- `dex/contracts/libraries/PoolAddress.sol`: deployment-specific pool init-code
  hash.
- `dex/contracts/lens/AgentswapQuoter.sol`: simulated quote recipient is the
  caller so gated-output quotes reflect the actual agent recipient.
- New gated-policy interfaces under `dex/contracts/interfaces/`.

`AgentswapRouter.sol` is an unmodified upstream periphery router. The upstream
Uniswap V3 core and periphery licenses and copyright notices remain in effect.

## License notes

The `AgentswapV3Factory` fork header is `GPL-2.0-or-later`. Upstream Uniswap V3
core sources under `dex/lib/v3-core` retain their upstream `BUSL-1.1` headers;
the upstream BUSL Change Date (`2023-04-01`) has passed and the Change License
is GPL-2.0-or-later.

The fork header was changed from the upstream identifier to
`GPL-2.0-or-later`. This is a comment-only source change: runtime bytecode is
unchanged, but the Solidity metadata hash differs from the deployed instance's
metadata. The BscScan verified source remains the authoritative record for the
deployed artifact.

## Source packaging note

The vendored trees in this repository contain the source and license files
needed to build the public contracts. They are not a complete copy of every
upstream test, review, or documentation file. The upstream commit pins above
identify the exact source revisions.
