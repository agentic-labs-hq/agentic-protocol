// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Asset classes supported by the protocol.
enum AssetType {
    FT,
    NFT
}

/// @notice Facility categories fixed for the current deployment.
/// @dev A new category is a new protocol version, not a the current deployment registry add.
enum FacilityCategory {
    NONE,
    POOL,
    LP_MANAGER,
    FEE_RECIPIENT,
    CUSTODY,
    PURPOSE
}

/// @notice Transfer kinds understood by the transfer policy.
enum TransferKind {
    TRANSFER
}

// Facility subtype registry labels.
bytes32 constant POOL = keccak256("POOL");
bytes32 constant NPM = keccak256("NPM");
bytes32 constant TREASURY = keccak256("TREASURY");
bytes32 constant VAULT = keccak256("VAULT");
bytes32 constant LAUNCH = keccak256("LAUNCH");
bytes32 constant LOCKER = keccak256("LOCKER");
bytes32 constant GAME = keccak256("GAME");
bytes32 constant ESCROW = keccak256("ESCROW");
bytes32 constant LENDING = keccak256("LENDING");
bytes32 constant MARKET = keccak256("MARKET"); // phase 2
