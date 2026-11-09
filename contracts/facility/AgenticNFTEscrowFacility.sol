// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NFT_ESCROW} from "../common/Types.sol";
import {INFTPurposeFacility, INFTEscrowFacility} from "../interfaces/INFTPurposeFacility.sol";
import {AgenticNFTFacilityBase} from "./AgenticNFTFacilityBase.sol";

/// @notice PURPOSE/NFT_ESCROW: role-controlled NFT escrow (INTERFACES v2.3 §NFT).
/// @dev Beneficiary or arbiter releases a held token id to an agent; the arbiter
/// refunds it. Settlement is ownership-based: once a token id leaves the
/// facility it is no longer held, so it cannot be released twice; the same id
/// may be deposited again and settled again. Agents deposit with a plain
/// `safeTransferFrom`; there is no `deposit` function and no native path.
contract AgenticNFTEscrowFacility is AgenticNFTFacilityBase, INFTEscrowFacility {
    /// @inheritdoc INFTEscrowFacility
    address public override arbiter;

    /// @inheritdoc INFTEscrowFacility
    address public override beneficiary;

    /// @notice Thrown when the arbiter is set to zero.
    error ZeroArbiter();
    /// @notice Thrown when the beneficiary is set to zero.
    error ZeroBeneficiary();
    /// @notice Thrown when the caller is neither beneficiary nor arbiter.
    error NotBeneficiaryOrArbiter(address caller);
    /// @notice Thrown when the caller is not the arbiter.
    error NotArbiter(address caller);
    /// @notice Thrown when `consume` is called; ESCROW has no sink.
    error ConsumeNotSupported();

    /// @param factory_ The NFT facility factory stamp; the factory's deployment helper enforces the caller.
    /// @param venueRegistry_ Venue registry for migration validation.
    /// @param nftRegistry_ NFT registry used to classify gated collections.
    /// @param owner_ Project owner (no Agent ID required).
    /// @param arbiter_ Dispute arbiter (may be zero; owner sets later).
    /// @param beneficiary_ Agent beneficiary (may be zero; owner sets later).
    constructor(
        address factory_,
        address venueRegistry_,
        address nftRegistry_,
        address owner_,
        // Optional roles may be zero and set later by the owner.
        // forge-lint: disable-next-line(missing-zero-check)
        address arbiter_,
        // forge-lint: disable-next-line(missing-zero-check)
        address beneficiary_
    ) AgenticNFTFacilityBase(factory_, NFT_ESCROW, venueRegistry_, nftRegistry_, owner_) {
        arbiter = arbiter_;
        if (beneficiary_ != address(0)) _requireAgent(beneficiary_);
        beneficiary = beneficiary_;
    }

    /// @inheritdoc INFTEscrowFacility
    function setArbiter(address arbiter_) external override onlyOwner {
        if (arbiter_ == address(0)) revert ZeroArbiter();
        arbiter = arbiter_;
        emit NFTArbiterSet(arbiter_);
    }

    /// @inheritdoc INFTEscrowFacility
    /// @dev Agent-only, never a facility.
    function setBeneficiary(address beneficiary_) external override onlyOwner {
        if (beneficiary_ == address(0)) revert ZeroBeneficiary();
        _requireAgent(beneficiary_);
        beneficiary = beneficiary_;
        emit NFTBeneficiarySet(beneficiary_);
    }

    /// @inheritdoc INFTPurposeFacility
    /// @dev Beneficiary or arbiter. The ownership check in `_checkNFTOutflow`
    /// prevents settling a token that already left the facility.
    function release(address collection, uint256 tokenId, address to) external override nonReentrant {
        if (msg.sender != beneficiary && msg.sender != arbiter) revert NotBeneficiaryOrArbiter(msg.sender);
        _checkNFTOutflow(collection, tokenId, to);
        emit NFTReleased(collection, tokenId, to);
        _sendNFT(collection, to, tokenId);
    }

    /// @inheritdoc INFTPurposeFacility
    /// @dev Arbiter-only. The ownership check in `_checkNFTOutflow` prevents
    /// settling a token that already left the facility.
    function refund(address collection, uint256 tokenId, address to) external override nonReentrant {
        if (msg.sender != arbiter) revert NotArbiter(msg.sender);
        _checkNFTOutflow(collection, tokenId, to);
        emit NFTRefunded(collection, tokenId, to);
        _sendNFT(collection, to, tokenId);
    }

    /// @inheritdoc INFTPurposeFacility
    /// @dev Not part of the ESCROW surface; always reverts.
    function consume(address, uint256) external pure override {
        revert ConsumeNotSupported();
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
