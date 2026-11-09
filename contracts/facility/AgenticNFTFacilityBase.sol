// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {FacilityCategory} from "../common/Types.sol";
import {IFacility, IMigratableFacility} from "../interfaces/IFacility.sol";
import {IFacilityFactory} from "../interfaces/IFacilityFactory.sol";
import {INFTRegistry} from "../interfaces/INFTRegistry.sol";
import {ITransferPolicy} from "../interfaces/ITransferPolicy.sol";
import {IVenueRegistry} from "../interfaces/IVenueRegistry.sol";

/// @notice Shared NFT custody/purpose facility base (INTERFACES v2.3 §NFT).
/// @dev The R2 condition is enforced by construction: only `factory` and
/// `facilityType` are immutable. Owner/pending owner, the registry addresses
/// and the migration target are storage, so two facilities of the same kind
/// deployed by the same factory share one runtime codehash.
///
/// None of the NFT facility templates has a native or generic ERC20 path. NFTs
/// enter by `safeTransferFrom` (no `deposit` function) and leave only through
/// the template's role-gated action. All gated outflows go through
/// `_checkNFTOutflow`: the facility must own the token, the recipient must be
/// non-zero, and for a gated collection the recipient must be an agent or the
/// single active migration target. Non-gated collections do not restrict the
/// recipient. The collection's own policy remains the final transfer authority.
///
/// `migrate` records the registry-approved replacement without moving tokens;
/// `migrateTokens` then moves the listed token ids to that target. This mirrors
/// the FT facility split between `migrate` and explicit asset movement.
abstract contract AgenticNFTFacilityBase is IFacility, IMigratableFacility, IERC721Receiver, ReentrancyGuard {
    /// @inheritdoc IFacility
    address public immutable override factory;

    /// @inheritdoc IFacility
    bytes32 public immutable override facilityType;

    /// @inheritdoc IFacility
    address public override owner;

    /// @inheritdoc IFacility
    address public override pendingOwner;

    /// @notice Venue registry used only for category/type/replacement checks.
    /// @dev Storage (not an immutable) so the runtime codehash is constant per
    /// factory/kind.
    address public venueRegistry;

    /// @notice Gated NFT collection registry used only to classify collections.
    /// @dev Storage (not an immutable) for the same R2 reason.
    address public nftRegistry;

    /// @dev Set by `migrate`; the only non-agent gated recipient. Accepted only
    /// while this facility is revoked and the registry still points at it.
    address private _migrationTarget;

    /// @notice Thrown when a required address is zero.
    error ZeroAddress();
    /// @notice Thrown when the caller is not the facility owner.
    error NotOwner(address caller);
    /// @notice Thrown when the caller is not the pending owner.
    error NotPendingOwner(address caller);
    /// @notice Thrown when a role or recipient is not an agent.
    error NotAgent(address account);
    /// @notice Thrown when a facility is used as an agent-only role/recipient.
    error FacilityNotAgent(address account);
    /// @notice Thrown when the replacement is this facility.
    error ReplacementIsSelf();
    /// @notice Thrown when this facility has not been revoked.
    error FacilityNotRevoked();
    /// @notice Thrown when the registry replacement is not the requested one.
    error NotRegistryReplacement(address expected, address actual);
    /// @notice Thrown when the replacement is not registered/active.
    error ReplacementNotActive(address replacement);
    /// @notice Thrown when the replacement has a different category.
    error ReplacementCategoryMismatch(address replacement, FacilityCategory expected, FacilityCategory actual);
    /// @notice Thrown when the replacement has a different subtype.
    error ReplacementTypeMismatch(address replacement, bytes32 expected, bytes32 actual);
    /// @notice Thrown when a recipient is zero.
    error ZeroRecipient();
    /// @notice Thrown when a gated recipient is not an agent (or target).
    error GatedRecipientNotAgent(address recipient);
    /// @notice Thrown when a gated recipient is a facility outside migration.
    error FacilityRecipientNotAllowed(address recipient);
    /// @notice Thrown when the facility does not currently own `tokenId`.
    error NotHeld(address collection, uint256 tokenId);
    /// @notice Thrown when `migrateTokens` runs before `migrate`.
    error MigrationTargetNotSet();
    /// @notice Thrown when the recorded migration target is no longer valid.
    error MigrationTargetNotActive(address target);

    /// @notice Emitted when the owner chooses the registry replacement.
    event FacilityMigrated(address indexed replacement);

    /// @param factory_ The NFT facility factory (immutable; also provides `policy()`).
    /// @param facilityType_ The registry subtype label (immutable).
    /// @param venueRegistry_ Venue registry used for migration checks.
    /// @param nftRegistry_ NFT registry used to classify gated collections.
    /// @param owner_ Project owner (storage; may be a non-agent EOA/multisig).
    constructor(address factory_, bytes32 facilityType_, address venueRegistry_, address nftRegistry_, address owner_) {
        if (
            factory_ == address(0) || venueRegistry_ == address(0) || nftRegistry_ == address(0) || owner_ == address(0)
        ) revert ZeroAddress();
        factory = factory_;
        facilityType = facilityType_;
        venueRegistry = venueRegistry_;
        nftRegistry = nftRegistry_;
        owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    /// @inheritdoc IFacility
    /// @dev Two-step; there is no renounce and no Agent ID requirement.
    function transferOwnership(address newOwner) external override onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /// @inheritdoc IFacility
    function acceptOwnership() external override {
        if (msg.sender != pendingOwner) revert NotPendingOwner(msg.sender);
        address previous = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, msg.sender);
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @inheritdoc IMigratableFacility
    /// @dev Owner-only, non-atomic migration. This function records the
    /// replacement; it never moves tokens. The facility must already be revoked
    /// and the registry replacement must be exactly `replacement`, active, and
    /// of the same category and subtype. Asset movement is a separate
    /// `migrateTokens` call.
    function migrate(address replacement) external override nonReentrant onlyOwner {
        if (replacement == address(0)) revert ZeroAddress();
        if (replacement == address(this)) revert ReplacementIsSelf();

        IVenueRegistry venue = IVenueRegistry(venueRegistry);
        if (!venue.isRevokedFacility(address(this))) revert FacilityNotRevoked();

        address expected = venue.replacementOf(address(this));
        if (expected != replacement) revert NotRegistryReplacement(expected, replacement);

        FacilityCategory category = venue.facilityCategory(address(this));
        if (category == FacilityCategory.NONE) revert ReplacementNotActive(replacement);
        FacilityCategory actualCategory = venue.facilityCategory(replacement);
        if (actualCategory != category) revert ReplacementCategoryMismatch(replacement, category, actualCategory);
        if (!venue.isFacilityOfCategory(replacement, category)) revert ReplacementNotActive(replacement);
        bytes32 actualType = venue.facilityType(replacement);
        if (actualType != facilityType) revert ReplacementTypeMismatch(replacement, facilityType, actualType);

        _migrationTarget = replacement;
        emit FacilityMigrated(replacement);
    }

    /// @notice Move the listed NFTs to the active migration target.
    /// @dev Owner-only and chunked so an unbounded collection cannot block the
    /// migration. Every token must be held by this facility at call time.
    function migrateTokens(address collection, uint256[] calldata tokenIds) external virtual onlyOwner nonReentrant {
        _migrateTokens(collection, tokenIds);
    }

    /// @notice The replacement recorded by `migrate` (zero before migration).
    function migrationTarget() external view returns (address) {
        return _migrationTarget;
    }

    /// @dev Shared `migrateTokens` body; re-used by every template override.
    function _migrateTokens(address collection, uint256[] calldata tokenIds) internal {
        address target = _migrationTarget;
        if (target == address(0)) revert MigrationTargetNotSet();
        if (!_isActiveMigrationTarget(target)) revert MigrationTargetNotActive(target);

        uint256 length = tokenIds.length;
        for (uint256 i; i < length; ++i) {
            uint256 tokenId = tokenIds[i];
            _requireHeld(collection, tokenId);
            _beforeMigrate(collection, tokenId);
            _sendNFT(collection, target, tokenId);
        }
    }

    /// @dev Template hook for assets that must never move again (GAME consume).
    function _beforeMigrate(address collection, uint256 tokenId) internal virtual {}

    /// @dev The canonical policy used only for agent-role validation. The
    /// per-collection policy still gates the actual transfer.
    function _transferPolicy() internal view returns (ITransferPolicy) {
        return ITransferPolicy(IFacilityFactory(factory).policy());
    }

    /// @dev Require a non-zero agent that is not a facility. Used for
    /// beneficiary roles and gated recipients.
    function _requireAgent(address account) internal view {
        if (account == address(0)) revert ZeroAddress();
        ITransferPolicy policy = _transferPolicy();
        // `categoryOf` keeps the category after revoke, unlike `isFacility`.
        // A revoked facility that somehow holds an Agent ID is still a facility.
        if (policy.categoryOf(account) != FacilityCategory.NONE) revert FacilityNotAgent(account);
        if (!policy.isMember(account)) revert NotAgent(account);
    }

    /// @dev True when the collection is recorded in the NFT registry as gated.
    function _isGatedNFT(address collection) internal view returns (bool) {
        return collection != address(0) && INFTRegistry(nftRegistry).isRegistered(collection);
    }

    /// @dev Require that this facility currently owns `tokenId`. A nonexistent
    /// token id or a collection that cannot answer `ownerOf` is reported as
    /// `NotHeld` too, so the facility error surface is deterministic.
    function _requireHeld(address collection, uint256 tokenId) internal view {
        if (collection != address(0)) {
            try IERC721(collection).ownerOf(tokenId) returns (address holder) {
                if (holder == address(this)) return;
            } catch {}
        }
        revert NotHeld(collection, tokenId);
    }

    /// @dev NFT outflow guard: the facility must own the token and the
    /// recipient must be non-zero. For a gated collection the recipient must be
    /// an agent or the single active migration target; facilities are never
    /// valid recipients outside migration. Non-gated collections are free.
    function _checkNFTOutflow(address collection, uint256 tokenId, address to) internal view {
        _requireHeld(collection, tokenId);
        if (to == address(0)) revert ZeroRecipient();
        if (!_isGatedNFT(collection)) return;
        if (_isActiveMigrationTarget(to)) return;

        ITransferPolicy policy = _transferPolicy();
        // `categoryOf` is kept after revoke; a revoked facility is never a
        // valid gated recipient outside the active migration target.
        if (policy.categoryOf(to) != FacilityCategory.NONE) revert FacilityRecipientNotAllowed(to);
        if (!policy.isMember(to)) revert GatedRecipientNotAgent(to);
    }

    /// @dev The target exception is live: both the revocation flag and the
    /// registry replacement must still point at the recorded target, and the
    /// target must still be active with the same category and subtype.
    function _isActiveMigrationTarget(address to) internal view returns (bool) {
        if (_migrationTarget == address(0) || to != _migrationTarget) return false;

        IVenueRegistry venue = IVenueRegistry(venueRegistry);
        if (!venue.isRevokedFacility(address(this))) return false;
        if (venue.replacementOf(address(this)) != to) return false;

        FacilityCategory category = venue.facilityCategory(address(this));
        if (category == FacilityCategory.NONE) return false;
        if (!venue.isFacilityOfCategory(to, category)) return false;
        return venue.facilityType(to) == facilityType;
    }

    /// @dev Single NFT transfer primitive. The collection's policy still runs.
    function _sendNFT(address collection, address to, uint256 tokenId) internal {
        IERC721(collection).transferFrom(address(this), to, tokenId);
    }
}
