// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {FacilityCategory} from "../common/Types.sol";
import {IAssetRegistry} from "../interfaces/IAssetRegistry.sol";
import {IFacility, IMigratableFacility} from "../interfaces/IFacility.sol";
import {IFacilityFactory} from "../interfaces/IFacilityFactory.sol";
import {ITransferPolicy} from "../interfaces/ITransferPolicy.sol";
import {IVenueRegistry} from "../interfaces/IVenueRegistry.sol";

/// @notice Shared CUSTODY/PURPOSE facility base.
/// @dev The R2 condition is enforced by construction: only `factory` and
/// `facilityType` are immutable. Owner/pending owner, the venue registry, the
/// asset registry, roles, token state, unlock data and the migration target are
/// storage. Two facilities of the same kind therefore have the same runtime
/// codehash.
///
/// All gated outflows go through `_checkGatedRecipient`, which requires an agent
/// under the factory's canonical policy or the single active migration target.
/// The token's own policy remains the final authority for the actual transfer.
/// There is no proxy, arbitrary call, delegatecall, public release or project
/// withdrawal path.
abstract contract AgenticFacilityBase is IFacility, IMigratableFacility, ReentrancyGuard {
    /// @inheritdoc IFacility
    address public immutable override factory;

    /// @inheritdoc IFacility
    bytes32 public immutable override facilityType;

    /// @inheritdoc IFacility
    address public override owner;

    /// @inheritdoc IFacility
    address public override pendingOwner;

    /// @dev Registry used only for facility category/type and replacement
    /// validation. Storage (not an immutable) so the runtime codehash is
    /// constant per factory/kind.
    address internal _venueRegistry;

    /// @dev Asset registry used to distinguish gated tokens from public ERC20.
    /// Storage (not an immutable) for the same R2 reason.
    address internal _assetRegistry;

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
    /// @notice Thrown when a gated recipient is zero.
    error ZeroRecipient();
    /// @notice Thrown when a gated recipient is not an agent (or target).
    error GatedRecipientNotAgent(address recipient);
    /// @notice Thrown when a gated recipient is a facility outside migration.
    error FacilityRecipientNotAllowed(address recipient);
    /// @notice Thrown when the token argument is zero.
    error ZeroToken();
    /// @notice Thrown when a gated-only function receives a public token.
    error NotGatedToken(address token);

    /// @notice Emitted when the owner chooses the registry replacement.
    event FacilityMigrated(address indexed replacement);

    /// @param factory_ The facility factory (immutable; also provides `policy()`).
    /// @param facilityType_ The registry subtype label (immutable).
    /// @param venueRegistry_ Venue registry used for migration checks.
    /// @param assetRegistry_ Asset registry used to classify gated vs public ERC20.
    /// @param owner_ Project owner (storage; may be a non-agent EOA/multisig).
    constructor(
        address factory_,
        bytes32 facilityType_,
        address venueRegistry_,
        address assetRegistry_,
        address owner_
    ) {
        if (
            factory_ == address(0) || venueRegistry_ == address(0) || assetRegistry_ == address(0)
                || owner_ == address(0)
        ) revert ZeroAddress();
        factory = factory_;
        facilityType = facilityType_;
        _venueRegistry = venueRegistry_;
        _assetRegistry = assetRegistry_;
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

    /// @inheritdoc IMigratableFacility
    /// @dev Owner-only, non-atomic migration. This function records the
    /// replacement; it never moves tokens or native. The facility must already
    /// be revoked and the registry replacement must be exactly `replacement`,
    /// active, and of the same category and subtype. After this call the
    /// existing gated-out functions may send to the target only while the
    /// facility is revoked and the registry still points at it.
    function migrate(address replacement) external override nonReentrant onlyOwner {
        if (replacement == address(0)) revert ZeroAddress();
        if (replacement == address(this)) revert ReplacementIsSelf();

        IVenueRegistry venue = IVenueRegistry(_venueRegistry);
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

    /// @notice The replacement recorded by `migrate` (zero before migration).
    function migrationTarget() external view returns (address) {
        return _migrationTarget;
    }

    /// @dev The canonical policy used only for agent-role validation. The
    /// per-token policy still gates the actual transfer.
    function _transferPolicy() internal view returns (ITransferPolicy) {
        return ITransferPolicy(IFacilityFactory(factory).policy());
    }

    /// @dev Require a non-zero agent that is not a facility. Used for
    /// beneficiary/depositor/lender/borrower roles and gated recipients.
    function _requireAgent(address account) internal view {
        if (account == address(0)) revert ZeroAddress();
        ITransferPolicy policy = _transferPolicy();
        // `categoryOf` keeps the category after revoke, unlike `isFacility`.
        // A revoked facility that somehow holds an Agent ID is still a facility.
        if (policy.categoryOf(account) != FacilityCategory.NONE) revert FacilityNotAgent(account);
        if (!policy.isMember(account)) revert NotAgent(account);
    }

    /// @dev True when the token is recorded in the asset registry as gated.
    function _isGated(address token) internal view returns (bool) {
        return token != address(0) && IAssetRegistry(_assetRegistry).isRegistered(token);
    }

    /// @dev Gated-only token guard used by PURPOSE/LOCKER and by VAULT/LAUNCH
    /// gated branches. Public ERC20 handling is explicit in VAULT/LAUNCH.
    function _checkGatedToken(address token) internal view {
        if (token == address(0)) revert ZeroToken();
        if (!_isGated(token)) revert NotGatedToken(token);
    }

    /// @dev Gated outflow guard: the token must be gated, and the recipient
    /// must be an agent, or the single active migration target. Facilities are
    /// never valid recipients outside migration. The token's own policy is
    /// checked by the token transfer.
    function _checkGatedRecipient(address token, address to) internal view {
        _checkGatedToken(token);
        if (to == address(0)) revert ZeroRecipient();
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

        IVenueRegistry venue = IVenueRegistry(_venueRegistry);
        if (!venue.isRevokedFacility(address(this))) return false;
        if (venue.replacementOf(address(this)) != to) return false;

        FacilityCategory category = venue.facilityCategory(address(this));
        if (category == FacilityCategory.NONE) return false;
        if (!venue.isFacilityOfCategory(to, category)) return false;
        return venue.facilityType(to) == facilityType;
    }

    /// @dev Public native outflow. Native is a public asset, so there is no
    /// agent restriction; only the function-level owner/role check applies.
    function _sendNative(address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroRecipient();
        // forge-lint: disable-next-line(arbitrary-send-eth)
        Address.sendValue(payable(to), amount);
    }
}
