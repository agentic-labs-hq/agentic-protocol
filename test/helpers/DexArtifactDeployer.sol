// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

/// @notice Loads the separately built `dex` (solc 0.7.6) artifacts into the
/// root 0.8.20 test VM.
/// @dev cross-version build order: `cd dex && forge build` (or `make dex-build`) before
/// running this test. The artifacts are read from `dex/out` through the
/// test-only `fs_permissions` read entry in the root `foundry.toml`; no 0.7.6
/// source or root compiler setting is shared or changed.
///
/// Only addresses are passed across the version boundary; every constructor
/// argument below is a plain ABI value (address), so no cross-version struct is
/// encoded here.
library DexArtifactDeployer {
    address internal constant VM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    Vm internal constant VM = Vm(VM_ADDRESS);

    string internal constant FACTORY_ARTIFACT = "dex/out/AgentswapV3Factory.sol/AgentswapV3Factory.json";
    string internal constant SWAP_ROUTER_ARTIFACT = "dex/out/AgentswapRouter.sol/AgentswapRouter.json";
    string internal constant QUOTER_ARTIFACT = "dex/out/AgentswapQuoter.sol/AgentswapQuoter.json";
    string internal constant NPM_ARTIFACT = "dex/out/AgentswapPositionManager.sol/AgentswapPositionManager.json";

    /// @notice Reverts with an actionable message when the dex project has not
    /// been built, instead of failing deep inside a `vm.getCode` lookup.
    function requireArtifacts() internal view {
        require(
            VM.exists(FACTORY_ARTIFACT) && VM.exists(SWAP_ROUTER_ARTIFACT) && VM.exists(QUOTER_ARTIFACT)
                && VM.exists(NPM_ARTIFACT),
            "cross-version: dex artifacts missing; build dex first (make dex-build)"
        );
    }

    /// @notice Deploys the M4 gated V3 factory (only the wrapper may create pools).
    function deployFactory() internal returns (address factory) {
        factory = VM.deployCode(FACTORY_ARTIFACT);
    }

    /// @notice Deploys the unmodified 0.7.6 AgentswapRouter(factory, WETH9).
    function deploySwapRouter(address factory, address weth9) internal returns (address router) {
        router = VM.deployCode(SWAP_ROUTER_ARTIFACT, abi.encode(factory, weth9));
    }

    /// @notice Deploys the unmodified 0.7.6 AgentswapQuoter(factory, WETH9).
    function deployQuoter(address factory, address weth9) internal returns (address quoter) {
        quoter = VM.deployCode(QUOTER_ARTIFACT, abi.encode(factory, weth9));
    }

    /// @notice Deploys the gated NPM
    /// `AgentswapPositionManager(factory, WETH9, descriptor, assetRegistry)`.
    /// @dev `assetRegistry` is the root protocol registry; the NPM reads it with its
    /// own 0.7.6 ABI selectors (`isRegistered`, `policyOf`).
    function deployNonfungiblePositionManager(address factory, address weth9, address descriptor, address assetRegistry)
        internal
        returns (address npm)
    {
        npm = VM.deployCode(NPM_ARTIFACT, abi.encode(factory, weth9, descriptor, assetRegistry));
    }
}
