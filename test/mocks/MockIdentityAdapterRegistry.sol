// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal identity adapter registry mock for policy tests.
/// @dev Only `adapterOf` is consumed by `AgenticPolicy`; the production registry owns the real
/// registry behavior and its tests.
contract MockIdentityAdapterRegistry {
    mapping(bytes32 => address) public adapterOf;

    function setAdapter(bytes32 kind, address adapter) external {
        adapterOf[kind] = adapter;
    }
}
