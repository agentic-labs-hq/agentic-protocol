// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NFT_GAME} from "../common/Types.sol";
import {INFTPurposeFacility, INFTGameFacility} from "../interfaces/INFTPurposeFacility.sol";
import {AgenticNFTFacilityBase} from "./AgenticNFTFacilityBase.sol";

/// @notice PURPOSE/NFT_GAME sink (INTERFACES v2.3 §NFT).
/// @dev The owner-set operator consumes (permanently locks) a held token id
/// without changing collection supply, or releases/refunds it only to agents.
/// Consumed ids can never leave and can never be released or refunded. Agents
/// deposit with a plain `safeTransferFrom`; there is no `deposit` function, no
/// project withdrawal and no native path.
contract AgenticNFTGameFacility is AgenticNFTFacilityBase, INFTGameFacility {
    /// @inheritdoc INFTGameFacility
    address public override operator;

    /// @notice Permanent game sink per collection/token id.
    mapping(address => mapping(uint256 => bool)) public consumed;

    /// @notice Thrown when the operator is set to zero.
    error ZeroOperator();
    /// @notice Thrown when the caller is not the operator.
    error NotOperator(address caller);
    /// @notice Thrown when the token id is already permanently consumed.
    error TokenConsumed(address collection, uint256 tokenId);

    /// @param factory_ The NFT facility factory stamp; the factory's deployment helper enforces the caller.
    /// @param venueRegistry_ Venue registry for migration validation.
    /// @param nftRegistry_ NFT registry used to classify gated collections.
    /// @param owner_ Project owner (no Agent ID required).
    /// @param operator_ Game operator (may be zero; owner sets later).
    constructor(
        address factory_,
        address venueRegistry_,
        address nftRegistry_,
        address owner_,
        // Optional; the owner may set it later.
        // forge-lint: disable-next-line(missing-zero-check)
        address operator_
    )
        AgenticNFTFacilityBase(factory_, NFT_GAME, venueRegistry_, nftRegistry_, owner_)
    {
        operator = operator_;
    }

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator(msg.sender);
        _;
    }

    /// @inheritdoc INFTGameFacility
    function setOperator(address operator_) external override onlyOwner {
        if (operator_ == address(0)) revert ZeroOperator();
        operator = operator_;
        emit NFTOperatorSet(operator_);
    }

    /// @inheritdoc INFTPurposeFacility
    /// @dev Locks `tokenId` in the sink. No transfer and no supply change;
    /// consumed ids are permanently unavailable to release/refund.
    function consume(address collection, uint256 tokenId) external override nonReentrant onlyOperator {
        if (consumed[collection][tokenId]) revert TokenConsumed(collection, tokenId);
        _requireHeld(collection, tokenId);
        consumed[collection][tokenId] = true;
        emit NFTConsumed(collection, tokenId);
    }

    /// @inheritdoc INFTPurposeFacility
    /// @dev Operator-only reward; recipient must be an agent (or target).
    function release(address collection, uint256 tokenId, address to) external override nonReentrant onlyOperator {
        if (consumed[collection][tokenId]) revert TokenConsumed(collection, tokenId);
        _checkNFTOutflow(collection, tokenId, to);
        emit NFTReleased(collection, tokenId, to);
        _sendNFT(collection, to, tokenId);
    }

    /// @inheritdoc INFTPurposeFacility
    /// @dev Operator-only refund; recipient must be an agent (or target).
    function refund(address collection, uint256 tokenId, address to) external override nonReentrant onlyOperator {
        if (consumed[collection][tokenId]) revert TokenConsumed(collection, tokenId);
        _checkNFTOutflow(collection, tokenId, to);
        emit NFTRefunded(collection, tokenId, to);
        _sendNFT(collection, to, tokenId);
    }

    /// @dev Consumed ids are permanent sinks: they can never be migrated.
    function _beforeMigrate(address collection, uint256 tokenId) internal view override {
        if (consumed[collection][tokenId]) revert TokenConsumed(collection, tokenId);
    }

    /// @inheritdoc INFTPurposeFacility
    /// @dev Diamond resolution: the base implements the body, the interface
    /// declares the selector.
    function migrateTokens(address collection, uint256[] calldata tokenIds)
        external
        override(AgenticNFTFacilityBase, INFTPurposeFacility)
        onlyOwner
        nonReentrant
    {
        _migrateTokens(collection, tokenIds);
    }
}
