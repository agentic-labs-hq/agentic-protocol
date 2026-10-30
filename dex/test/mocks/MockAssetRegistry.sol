// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

/// @notice Test-only asset registry: `isRegistered` + per-asset `policyOf`.
/// @dev No governance, no restrictions; the NPM never calls anything else.
contract MockAssetRegistry {
    mapping(address => bool) private _registered;
    mapping(address => address) private _policyOf;

    function setRegistered(address asset, bool registered) external {
        _registered[asset] = registered;
    }

    function setPolicy(address asset, address policy) external {
        _policyOf[asset] = policy;
    }

    function isRegistered(address asset) external view returns (bool) {
        return _registered[asset];
    }

    function policyOf(address asset) external view returns (address) {
        return _policyOf[asset];
    }
}
