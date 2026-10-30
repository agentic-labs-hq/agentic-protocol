// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Canonical identity kind label for the Agent ID adapter.
// Integration constant shared with the policy layer; not a public interface.
bytes32 constant AGENT_ID_KIND = keccak256("AGENT_ID");

/// @notice Adapter-specific ABI for the external Agent ID registry.
/// @dev Not frozen. The live BSC mainnet registry is
/// `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`. The three functions below were
/// verified against the verified Sourcify ABI, the runtime selectors
/// (`0x70a08231`, `0xc50a1514`, `0x1da94fb4`) and BSC fork reads.
///
/// The registry is a third-party dependency: this project does not deploy it.
/// The adapter deliberately depends on only these three reads.
interface IAgentIdRegistry {
    /// @notice Number of Agent IDs bound to `wallet` (0 or 1 in practice).
    function balanceOf(address wallet) external view returns (uint256);

    /// @notice Agent ID handle bound to `wallet` (bare string, no `.ai` suffix);
    /// empty when the wallet has no Agent ID.
    function handleOf(address wallet) external view returns (string memory);

    /// @notice Wallet that owns `handle`; zero when the handle is unbound.
    function ownerOfHandle(string calldata handle) external view returns (address);
}
