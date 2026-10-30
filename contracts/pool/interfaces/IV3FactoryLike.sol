// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal 0.8.20 ABI of the pinned Uniswap V3 core factory.
/// @dev Local ABI only: no 0.7.6 import and no cross-version structs. The
/// canonical factory is the vendored V3 core; only the methods the wrapper
/// calls are declared here.
interface IV3FactoryLike {
    function owner() external view returns (address);

    function feeAmountTickSpacing(uint24 fee) external view returns (int24);

    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);

    function setOwner(address newOwner) external;

    function enableFeeAmount(uint24 fee, int24 tickSpacing) external;
}
