// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FacilityCategory} from "../common/Types.sol";
import {NonRevocableFacility} from "../common/Errors.sol";
import {Governance2Step} from "../common/Governance2Step.sol";
import {IFacility} from "../interfaces/IFacility.sol";
import {IFacilityFactory} from "../interfaces/IFacilityFactory.sol";
import {IVenueRegistry} from "../interfaces/IVenueRegistry.sol";

/// @notice Facility (venue) registry.
/// @dev Subtype -> category is append-only. Facilities are registered by a
/// per-category registrar; CUSTODY/PURPOSE additionally prove the factory stamp,
/// subtype and template runtime codehash. POOL/LP_MANAGER are not revocable.
/// Revoking keeps type/category/factory and freezes the facility; only a
/// same-category/same-subtype replacement can receive its gated assets.
contract AgenticVenueRegistry is IVenueRegistry, Governance2Step {
    /// @inheritdoc IVenueRegistry
    mapping(bytes32 => FacilityCategory) public override categoryOfType;

    /// @inheritdoc IVenueRegistry
    mapping(address => mapping(FacilityCategory => bool)) public override isRegistrarFor;

    /// @inheritdoc IVenueRegistry
    mapping(address => bytes32) public override facilityType;

    /// @inheritdoc IVenueRegistry
    mapping(address => FacilityCategory) public override facilityCategory;

    /// @inheritdoc IVenueRegistry
    mapping(address => bool) public override isRevokedFacility;

    /// @inheritdoc IVenueRegistry
    mapping(address => address) public override replacementOf;

    /// @inheritdoc IVenueRegistry
    mapping(address => address) public override factoryOf;

    mapping(address => bool) private _registered;

    error ZeroKind();
    error CategoryNone();
    error ZeroAccount();
    error ZeroReplacement();
    error TypeAlreadyMapped(bytes32 kind, FacilityCategory existing);
    error TypeNotMapped(bytes32 kind);
    error NotRegistrar(address caller, FacilityCategory category);
    error AccountHasNoCode(address account);
    error FacilityAlreadyRegistered(address account);
    error FacilityNotRegistered(address account);
    error FacilityNotActive(address account);
    error FactoryMismatch(address account, address expected, address actual);
    error FacilityTypeMismatch(address account, bytes32 expected, bytes32 actual);
    error CodehashMismatch(address account, bytes32 expected, bytes32 actual);
    error FacilityNotOwner(address account, address caller);
    error ReplacementNotApplicable(address account);
    error ReplacementIsSelf(address account);
    error ReplacementNotActive(address replacement);
    error ReplacementCategoryMismatch(address replacement, FacilityCategory expected, FacilityCategory actual);
    error ReplacementTypeMismatch(address replacement, bytes32 expected, bytes32 actual);

    constructor(address governance_) Governance2Step(governance_) {}

    /// @inheritdoc IVenueRegistry
    function isFacility(address account) public view override returns (bool) {
        return _registered[account] && !isRevokedFacility[account];
    }

    /// @inheritdoc IVenueRegistry
    function isFacilityOfCategory(address account, FacilityCategory category) external view override returns (bool) {
        return isFacility(account) && facilityCategory[account] == category;
    }

    /// @inheritdoc IVenueRegistry
    function isFacilityOfType(address account, bytes32 kind) external view override returns (bool) {
        return isFacility(account) && facilityType[account] == kind;
    }

    /// @inheritdoc IVenueRegistry
    /// @dev Append-only: an existing subtype's category can never be changed.
    function addTypeCategory(bytes32 kind, FacilityCategory category) external override onlyGovernance {
        if (kind == bytes32(0)) revert ZeroKind();
        if (category == FacilityCategory.NONE) revert CategoryNone();
        FacilityCategory existing = categoryOfType[kind];
        if (existing != FacilityCategory.NONE) revert TypeAlreadyMapped(kind, existing);

        categoryOfType[kind] = category;
        emit TypeCategoryAdded(kind, category);
    }

    /// @inheritdoc IVenueRegistry
    function setRegistrar(address account, FacilityCategory category, bool enabled) external override onlyGovernance {
        if (account == address(0)) revert ZeroAccount();
        if (category == FacilityCategory.NONE) revert CategoryNone();
        if (account.code.length == 0) revert AccountHasNoCode(account);

        // RegistrarSet is emitted below; the heuristic does not see it here.
        // forge-lint: disable-next-line(missing-events-access-control)
        isRegistrarFor[account][category] = enabled;
        emit RegistrarSet(account, category, enabled);
    }

    /// @inheritdoc IVenueRegistry
    /// @dev CUSTODY/PURPOSE must be created by the registrar factory and match
    /// the factory's template codehash (rejects proxies/arbitrary code).
    /// POOL/LP_MANAGER/FEE_RECIPIENT trust the per-category registrar; that is a
    /// deployment policy in the current deployment, not an on-chain DEX cap.
    function registerFacility(address account, bytes32 kind) external override {
        FacilityCategory category = categoryOfType[kind];
        if (category == FacilityCategory.NONE) revert TypeNotMapped(kind);
        if (!isRegistrarFor[msg.sender][category]) revert NotRegistrar(msg.sender, category);
        if (account == address(0)) revert ZeroAccount();
        if (account.code.length == 0) revert AccountHasNoCode(account);
        if (_registered[account]) revert FacilityAlreadyRegistered(account);

        if (category == FacilityCategory.CUSTODY || category == FacilityCategory.PURPOSE) {
            address actualFactory = IFacility(account).factory();
            if (actualFactory != msg.sender) revert FactoryMismatch(account, msg.sender, actualFactory);

            bytes32 actualType = IFacility(account).facilityType();
            if (actualType != kind) revert FacilityTypeMismatch(account, kind, actualType);

            bytes32 actualCodehash = account.codehash;
            bytes32 expectedCodehash = IFacilityFactory(msg.sender).codehashOf(kind);
            if (actualCodehash != expectedCodehash) {
                revert CodehashMismatch(account, expectedCodehash, actualCodehash);
            }
        }

        _registered[account] = true;
        facilityType[account] = kind;
        facilityCategory[account] = category;
        factoryOf[account] = msg.sender;

        emit FacilityRegistered(account, kind, category, msg.sender);
    }

    /// @inheritdoc IVenueRegistry
    function revokeFacility(address account) external override onlyGovernance {
        if (!_registered[account]) revert FacilityNotRegistered(account);
        if (isRevokedFacility[account]) revert FacilityNotActive(account);

        FacilityCategory category = facilityCategory[account];
        if (category == FacilityCategory.POOL || category == FacilityCategory.LP_MANAGER) {
            revert NonRevocableFacility();
        }

        // Keep type/category/factory; only the active flag changes.
        isRevokedFacility[account] = true;
        emit FacilityRevoked(account, facilityType[account]);
    }

    /// @inheritdoc IVenueRegistry
    /// @dev CUSTODY/PURPOSE: the facility owner chooses its own replacement.
    /// FEE_RECIPIENT: governance chooses. The replacement must be active, of the
    /// same category and same subtype, and cannot be the facility itself.
    function setReplacement(address account, address replacement) external override {
        if (!_registered[account]) revert FacilityNotRegistered(account);

        FacilityCategory category = facilityCategory[account];
        if (category == FacilityCategory.POOL || category == FacilityCategory.LP_MANAGER) {
            revert ReplacementNotApplicable(account);
        }

        if (category == FacilityCategory.FEE_RECIPIENT) {
            _checkGovernance();
        } else {
            if (IFacility(account).owner() != msg.sender) revert FacilityNotOwner(account, msg.sender);
        }

        if (replacement == address(0)) revert ZeroReplacement();
        if (replacement == account) revert ReplacementIsSelf(account);
        if (!isFacility(replacement)) revert ReplacementNotActive(replacement);

        FacilityCategory replacementCategory = facilityCategory[replacement];
        if (replacementCategory != category) {
            revert ReplacementCategoryMismatch(replacement, category, replacementCategory);
        }

        bytes32 expectedType = facilityType[account];
        if (facilityType[replacement] != expectedType) {
            revert ReplacementTypeMismatch(replacement, expectedType, facilityType[replacement]);
        }

        replacementOf[account] = replacement;
        emit ReplacementSet(account, replacement);
    }
}
