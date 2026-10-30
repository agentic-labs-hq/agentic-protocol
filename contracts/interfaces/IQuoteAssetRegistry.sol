// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGovernance} from "./IGovernance.sol";

/// @notice Quote asset registry interface.
interface IQuoteAssetRegistry is IGovernance {
    function assetRegistry() external view returns (address);
    function maxQuoteAssets() external view returns (uint256);
    function isQuoteAsset(address token) external view returns (bool);
    function quoteAssets() external view returns (address[] memory);

    function addQuoteAsset(address token) external;
    function removeQuoteAsset(address token) external;

    event QuoteAssetAdded(address indexed token);
    event QuoteAssetRemoved(address indexed token);
}
