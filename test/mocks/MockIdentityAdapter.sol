// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IIdentityAdapter} from "../../contracts/interfaces/IIdentityAdapter.sol";

/// @notice Minimal Agent ID adapter mock for policy tests.
contract MockIdentityAdapter is IIdentityAdapter {
    bytes32 public immutable override kind;
    uint256 public immutable override version;
    uint256 public immutable override chainId;

    mapping(address => bool) private _hasIdentity;

    error NoIdentity(address wallet);

    constructor(bytes32 kind_, uint256 version_, uint256 chainId_) {
        kind = kind_;
        version = version_;
        chainId = chainId_;
    }

    function setHasIdentity(address wallet, bool hasIdentity_) external {
        _hasIdentity[wallet] = hasIdentity_;
    }

    function hasIdentity(address wallet) external view override returns (bool) {
        return _hasIdentity[wallet];
    }

    function identityOf(address wallet) external view override returns (uint256 tokenId, bytes32 handleHash) {
        if (!_hasIdentity[wallet]) revert NoIdentity(wallet);
        handleHash = keccak256(abi.encodePacked(wallet));
        tokenId = uint256(handleHash);
    }

    function requireIdentity(address wallet) external view override returns (uint256 tokenId, bytes32 handleHash) {
        if (!_hasIdentity[wallet]) revert NoIdentity(wallet);
        handleHash = keccak256(abi.encodePacked(wallet));
        tokenId = uint256(handleHash);
    }
}
