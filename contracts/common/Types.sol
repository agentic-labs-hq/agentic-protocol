// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Asset classes supported by the protocol (INTERFACES v2.2 §2).
enum AssetType {
    FT,
    NFT
}

/// @notice Facility categories fixed for Phase 1 (INTERFACES v2.2 §2).
/// @dev A new category is a new protocol version, not a Phase 1 registry add.
enum FacilityCategory {
    NONE,
    POOL,
    LP_MANAGER,
    FEE_RECIPIENT,
    CUSTODY,
    PURPOSE
}

/// @notice Transfer kinds understood by the transfer policy (INTERFACES v2.2 §2).
enum TransferKind {
    TRANSFER
}

// Facility subtype registry labels (INTERFACES v2.2 §2).
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

// NFT facility subtype registry labels (phase 2, INTERFACES v2.3 §NFT).
// CUSTODY: funded by mint only. PURPOSE: agents may deposit and withdraw.
bytes32 constant NFT_VAULT = keccak256("NFT_VAULT");
bytes32 constant NFT_LAUNCH = keccak256("NFT_LAUNCH");
bytes32 constant NFT_LOCKER = keccak256("NFT_LOCKER");
bytes32 constant NFT_GAME = keccak256("NFT_GAME");
bytes32 constant NFT_ESCROW = keccak256("NFT_ESCROW");
