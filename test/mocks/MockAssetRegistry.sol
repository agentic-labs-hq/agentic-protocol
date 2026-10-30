// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal asset-registry mock: only the gated flag the treasury reads.
/// @dev `AgenticTreasury` only calls `isRegistered`; the rest of the registry
/// surface is irrelevant to these tests and deliberately omitted.
contract MockAssetRegistry {
    mapping(address => bool) private _registered;

    function setRegistered(address asset, bool registered) external {
        _registered[asset] = registered;
    }

    function isRegistered(address asset) external view returns (bool) {
        return _registered[asset];
    }
}
