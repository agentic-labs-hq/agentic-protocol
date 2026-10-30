// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IIdentityAdapter} from "../interfaces/IIdentityAdapter.sol";
import {AGENT_ID_KIND, IAgentIdRegistry} from "./IAgentIdRegistry.sol";

/// @title AgenticIdAdapter
/// @notice Read-only identity adapter for the external BSC Agent ID registry.
/// @dev Eligibility is evaluated with live registry reads on every call; there
/// is no cached identity state. Registry failures revert (fail-closed).
contract AgenticIdAdapter is IIdentityAdapter {
    /// @notice Thrown when `requireIdentity` is called for an ineligible wallet.
    error NotAgent(address wallet);

    /// @notice Thrown when the constructor receives a zero or codeless registry.
    error InvalidRegistry(address registry);

    /// @dev Adapter implementation version (v1).
    uint256 private constant _VERSION = 1;

    IAgentIdRegistry private immutable _registry;
    uint256 private immutable _chainId;

    /// @param registry_ Live external Agent ID registry. Must be a contract.
    constructor(IAgentIdRegistry registry_) {
        if (address(registry_) == address(0) || address(registry_).code.length == 0) {
            revert InvalidRegistry(address(registry_));
        }
        _registry = registry_;
        _chainId = block.chainid;
    }

    /// @inheritdoc IIdentityAdapter
    /// @dev True only when: `wallet != 0`, `balanceOf(wallet) > 0`,
    /// `handleOf(wallet)` is non-empty and `ownerOfHandle(handle) == wallet`.
    function hasIdentity(address wallet) external view override returns (bool) {
        (bool eligible,) = _probe(wallet);
        return eligible;
    }

    /// @inheritdoc IIdentityAdapter
    /// @dev Returns `(0, 0)` for an ineligible wallet. For an eligible wallet,
    /// `handleHash = keccak256(bytes(handleOf(wallet)))` and
    /// `tokenId = uint256(handleHash)`. The token id is a hash-derived label,
    /// not an enumerable ERC-721 id.
    function identityOf(address wallet) external view override returns (uint256 tokenId, bytes32 handleHash) {
        (bool eligible, string memory handle) = _probe(wallet);
        if (!eligible) return (0, bytes32(0));
        handleHash = keccak256(bytes(handle));
        tokenId = uint256(handleHash);
    }

    /// @inheritdoc IIdentityAdapter
    /// @dev Reverts with `NotAgent(wallet)` for an ineligible wallet; otherwise
    /// returns the same `(tokenId, handleHash)` values as `identityOf`.
    function requireIdentity(address wallet) external view override returns (uint256 tokenId, bytes32 handleHash) {
        (bool eligible, string memory handle) = _probe(wallet);
        if (!eligible) revert NotAgent(wallet);
        handleHash = keccak256(bytes(handle));
        tokenId = uint256(handleHash);
    }

    /// @inheritdoc IIdentityAdapter
    function kind() external pure override returns (bytes32) {
        return AGENT_ID_KIND;
    }

    /// @inheritdoc IIdentityAdapter
    function version() external pure override returns (uint256) {
        return _VERSION;
    }

    /// @inheritdoc IIdentityAdapter
    function chainId() external view override returns (uint256) {
        return _chainId;
    }

    /// @dev Exact eligibility probe. The zero wallet and zero-balance wallet
    /// short-circuit before `handleOf`; empty handles short-circuit before
    /// `ownerOfHandle`. All registry reads happen live, once per call.
    function _probe(address wallet) private view returns (bool eligible, string memory handle) {
        if (wallet == address(0)) return (false, "");
        IAgentIdRegistry registry_ = _registry;
        // Exact eligibility requires balanceOf(wallet) > 0.
        // forge-lint: disable-next-line(incorrect-strict-equality)
        if (registry_.balanceOf(wallet) == 0) return (false, "");
        handle = registry_.handleOf(wallet);
        if (bytes(handle).length == 0) return (false, "");
        if (registry_.ownerOfHandle(handle) != wallet) return (false, "");
        return (true, handle);
    }
}
