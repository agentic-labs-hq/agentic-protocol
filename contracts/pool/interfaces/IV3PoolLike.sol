// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal 0.8.20 ABI of a pinned Uniswap V3 core pool.
/// @dev Local ABI only: no 0.7.6 import and no cross-version structs. The
/// wrapper initializes the pool and manages its protocol fee; the getters are
/// the standard V3 pool surface.
interface IV3PoolLike {
    function initialize(uint160 sqrtPriceX96) external;

    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external;

    function collectProtocol(address recipient, uint128 amount0Requested, uint128 amount1Requested)
        external
        returns (uint128 amount0, uint128 amount1);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function fee() external view returns (uint24);
}
