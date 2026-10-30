// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal Uniswap-V3-pool-shaped account for `AgenticAssetRegistry.recordPool`.
/// @dev The registry only reads `token0()`/`token1()`; venue registration happens
/// separately through the real `AgenticVenueRegistry` POOL registrar path.
contract MockGatedPool {
    address public token0;
    address public token1;

    constructor(address token0_, address token1_) {
        token0 = token0_;
        token1 = token1_;
    }

    function setTokens(address token0_, address token1_) external {
        token0 = token0_;
        token1 = token1_;
    }
}
