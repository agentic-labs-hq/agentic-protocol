// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGovernance} from "./IGovernance.sol";

/// @notice Gated Uniswap V3 pool factory interface.
interface IGatedPoolFactory is IGovernance {
    function createPool(address tokenA, address tokenB, uint24 fee, uint160 sqrtPriceX96)
        external
        returns (address pool);

    function setProtocolFee(address pool, uint8 feeProtocol0, uint8 feeProtocol1) external;
    function collectProtocol(address pool, uint128 amount0Requested, uint128 amount1Requested)
        external
        returns (uint128 amount0, uint128 amount1);
    function setTreasury(address newTreasury) external;
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external;
    function transferCanonicalFactoryOwnership(address newOwner) external;

    function canonicalFactory() external view returns (address);
    function assetRegistry() external view returns (address);
    function quoteAssetRegistry() external view returns (address);
    function venueRegistry() external view returns (address);
    function policyRegistry() external view returns (address);
    function treasury() external view returns (address);
    function isAllowedFee(uint24 fee) external view returns (bool);

    event GatedPoolCreated(
        address indexed pool, address indexed token0, address indexed token1, uint24 fee, uint160 sqrtPriceX96
    );
    event ProtocolFeeSet(address indexed pool, uint8 feeProtocol0, uint8 feeProtocol1);
    event ProtocolCollected(address indexed pool, address indexed recipient, uint128 amount0, uint128 amount1);
    event TreasurySet(address indexed treasury);
    event FeeAmountEnabled(uint24 fee, int24 tickSpacing);
    event CanonicalFactoryOwnerChanged(address indexed newOwner);
}
