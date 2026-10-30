// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGovernance} from "./IGovernance.sol";

/// @notice Identity adapter interface.
interface IIdentityAdapter {
    function hasIdentity(address wallet) external view returns (bool);
    function identityOf(address wallet) external view returns (uint256 tokenId, bytes32 handleHash);
    function requireIdentity(address wallet) external view returns (uint256 tokenId, bytes32 handleHash);
    function kind() external view returns (bytes32);
    function version() external view returns (uint256);
    function chainId() external view returns (uint256);
}

/// @notice Identity adapter registry interface.
interface IIdentityAdapterRegistry is IGovernance {
    function maxAdapters() external view returns (uint256);
    function isEnabled(address adapter) external view returns (bool);
    function adapterOf(bytes32 kind) external view returns (address);
    function enabledAdapters() external view returns (address[] memory);

    function registerAdapter(address adapter, bytes32 kind) external;
    function replaceAdapter(address newAdapter) external;
    function disableAdapter(address adapter) external;

    event AdapterRegistered(address indexed adapter, bytes32 indexed kind);
    event AdapterReplaced(address indexed oldAdapter, address indexed newAdapter, bytes32 indexed kind);
    event AdapterDisabled(address indexed adapter, bytes32 indexed kind);
}
