// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NFT_LAUNCH} from "../common/Types.sol";
import {INFTCustodyFacility, INFTLaunchFacility} from "../interfaces/INFTCustodyFacility.sol";
import {AgenticNFTFacilityBase} from "./AgenticNFTFacilityBase.sol";

/// @notice CUSTODY/NFT_LAUNCH: primary NFT sale custody (INTERFACES v2.3 §NFT).
/// @dev Owner sets the project operator and the agent-only beneficiary. The
/// operator releases held NFTs to agent buyers before the sale closes. `close`
/// is owner-or-operator and marks the sale closed; after that `release` may
/// still send to the agent beneficiary or the active migration target. There
/// is no public release and no facility recipient (outside the migration
/// target).
contract AgenticNFTLaunchFacility is AgenticNFTFacilityBase, INFTLaunchFacility {
    /// @inheritdoc INFTLaunchFacility
    address public override operator;

    /// @inheritdoc INFTLaunchFacility
    address public override beneficiary;

    /// @notice Whether the primary sale has been closed by owner/operator.
    bool public closed;

    /// @notice Thrown when the operator is set to zero.
    error ZeroOperator();
    /// @notice Thrown when the beneficiary is set to zero.
    error ZeroBeneficiary();
    /// @notice Thrown when `close` runs twice.
    error AlreadyClosed();
    /// @notice Thrown when the caller is not the operator.
    error NotOperator(address caller);
    /// @notice Thrown when the caller is neither owner nor operator.
    error NotOwnerOrOperator(address caller);
    /// @notice Thrown when a closed sale releases to a non-beneficiary.
    error ClosedRecipientNotBeneficiary(address recipient);
    /// @notice Thrown when `close` runs before a beneficiary is set.
    error BeneficiaryNotSet();

    /// @param factory_ The NFT facility factory stamp; the factory's deployment helper enforces the caller.
    /// @param venueRegistry_ Venue registry for migration validation.
    /// @param nftRegistry_ NFT registry used to classify gated collections.
    /// @param owner_ Project owner (no Agent ID required).
    /// @param operator_ Project sale operator (may be zero; owner sets later).
    /// @param beneficiary_ Agent beneficiary for unsold inventory (may be zero).
    constructor(
        address factory_,
        address venueRegistry_,
        address nftRegistry_,
        address owner_,
        // Optional roles may be zero and set later by the owner.
        // forge-lint: disable-next-line(missing-zero-check)
        address operator_,
        // forge-lint: disable-next-line(missing-zero-check)
        address beneficiary_
    ) AgenticNFTFacilityBase(factory_, NFT_LAUNCH, venueRegistry_, nftRegistry_, owner_) {
        operator = operator_;
        if (beneficiary_ != address(0)) _requireAgent(beneficiary_);
        beneficiary = beneficiary_;
    }

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator(msg.sender);
        _;
    }

    modifier onlyOwnerOrOperator() {
        if (msg.sender != owner && msg.sender != operator) revert NotOwnerOrOperator(msg.sender);
        _;
    }

    /// @inheritdoc INFTLaunchFacility
    function setOperator(address operator_) external override onlyOwner {
        if (operator_ == address(0)) revert ZeroOperator();
        operator = operator_;
        emit NFTOperatorSet(operator_);
    }

    /// @inheritdoc INFTLaunchFacility
    /// @dev Agent-only, never a facility.
    function setBeneficiary(address beneficiary_) external override onlyOwner {
        if (beneficiary_ == address(0)) revert ZeroBeneficiary();
        _requireAgent(beneficiary_);
        beneficiary = beneficiary_;
        emit NFTBeneficiarySet(beneficiary_);
    }

    /// @inheritdoc INFTCustodyFacility
    /// @dev Operator-only primary sale to an agent (or the active migration
    /// target). After `close`, unsold NFTs may only go to the agent
    /// beneficiary, mirroring the FT LAUNCH template.
    function release(address collection, uint256 tokenId, address to) external override nonReentrant onlyOperator {
        if (closed && to != beneficiary && !_isActiveMigrationTarget(to)) {
            revert ClosedRecipientNotBeneficiary(to);
        }
        _checkNFTOutflow(collection, tokenId, to);
        emit NFTReleased(collection, tokenId, to);
        _sendNFT(collection, to, tokenId);
    }

    /// @inheritdoc INFTLaunchFacility
    /// @dev Owner or operator closes the primary sale. The beneficiary must be
    /// set to an agent so unsold NFTs have a valid recipient.
    function close() external override onlyOwnerOrOperator {
        if (closed) revert AlreadyClosed();
        if (beneficiary == address(0)) revert BeneficiaryNotSet();
        _requireAgent(beneficiary);
        closed = true;
        emit NFTClosed();
    }

    /// @inheritdoc INFTCustodyFacility
    /// @dev Diamond resolution: the base implements the body, the interface
    /// declares the selector. Both modifiers are re-applied here because an
    /// overriding function does not inherit them.
    function migrateTokens(address collection, uint256[] calldata tokenIds)
        external
        override(AgenticNFTFacilityBase, INFTCustodyFacility)
        onlyOwner
        nonReentrant
    {
        _migrateTokens(collection, tokenIds);
    }
}
