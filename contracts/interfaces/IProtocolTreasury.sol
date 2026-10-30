// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGovernance} from "./IGovernance.sol";
import {IMigratableFacility} from "./IFacility.sol";

/// @notice Protocol treasury / FEE_RECIPIENT interface.
interface IProtocolTreasury is IGovernance, IMigratableFacility {
    function router() external view returns (address);
    function facilityRegistry() external view returns (address);
    function assetRegistry() external view returns (address);
    function maxDistributionBatch() external view returns (uint256);

    function transferToken(address token, address to, uint256 amount) external;
    function transferNative(address payable to, uint256 amount) external;
    function swapExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) external returns (uint256 amountOut);
    function distributeToken(address token, address[] calldata recipients, uint256[] calldata amounts) external;

    receive() external payable;

    event TreasuryTransfer(address indexed token, address indexed to, uint256 amount);
    event TreasurySwap(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event TreasuryMigrated(address indexed replacement);
}
