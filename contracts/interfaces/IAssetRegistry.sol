// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGovernance} from "./IGovernance.sol";

/// @notice Gated asset registry interface.
interface IAssetRegistry is IGovernance {
    function policyRegistry() external view returns (address);
    function venueRegistry() external view returns (address);
    function maxPoolsPerAsset() external view returns (uint256);
    function isRegistered(address asset) external view returns (bool);
    function policyOf(address asset) external view returns (address);
    function creatorOf(address asset) external view returns (address);
    function poolsOf(address asset) external view returns (address[] memory);
    function isRegistrar(address account) external view returns (bool);

    function registerAsset(address asset, address policy, address creator) external;
    function recordPool(address asset, address pool) external;
    function setRegistrar(address account, bool enabled) external;

    event AssetRegistered(address indexed asset, address indexed policy, address indexed creator);
    event PoolRecorded(address indexed asset, address indexed pool);
    event RegistrarSet(address indexed account, bool enabled);
}
