// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ESCROW, FacilityCategory, GAME, LAUNCH, LOCKER, VAULT} from "../common/Types.sol";
import {IFacilityFactory} from "../interfaces/IFacilityFactory.sol";
import {ITransferPolicy} from "../interfaces/ITransferPolicy.sol";
import {IVenueRegistry} from "../interfaces/IVenueRegistry.sol";

import {
    AgenticGameTemplateDeployer,
    AgenticLaunchTemplateDeployer,
    AgenticLockerTemplateDeployer,
    AgenticVaultTemplateDeployer,
    FacilityTemplateDeployer
} from "./AgenticFacilityFactory.sol";
import {AgenticEscrowFacilityV2} from "./AgenticEscrowFacilityV2.sol";

/// @notice Facility factory v2. Public builder set: VAULT, LAUNCH, LOCKER,
/// GAME, and balance-based ESCROW. LENDING is intentionally not supported.
/// @dev Reuses the deployed v1 template helpers for the four unchanged
/// templates and a new helper for ESCROW v2. The factory deploys one canonical
/// instance per kind to record its runtime codehash; it never holds assets.
contract AgenticFacilityFactoryV2 is IFacilityFactory {
    struct TemplateDeployers {
        address vault;
        address launch;
        address locker;
        address game;
        address escrow;
    }

    address public immutable override policy;
    address public immutable venueRegistry;
    address public immutable assetRegistry;

    address public immutable vaultDeployer;
    address public immutable launchDeployer;
    address public immutable lockerDeployer;
    address public immutable gameDeployer;
    address public immutable escrowDeployer;

    mapping(bytes32 => bool) private _supported;
    mapping(bytes32 => bytes32) private _codehash;

    error ZeroAddress();
    error RegistryHasNoCode(address account);
    error DeployerHasNoCode(address account);
    error UnsupportedFacilityType(bytes32 kind);
    error InvalidOwner();
    error AgentRequired(address account);
    error FacilityNotAgent(address account);
    error TemplateCodehashMismatch(bytes32 kind, bytes32 expected, bytes32 actual);
    error EscrowRolesRequired();
    error LockerBeneficiaryRequired();

    constructor(address policy_, address venueRegistry_, address assetRegistry_, TemplateDeployers memory deployers_) {
        if (policy_ == address(0) || venueRegistry_ == address(0) || assetRegistry_ == address(0)) {
            revert ZeroAddress();
        }
        if (policy_.code.length == 0) revert RegistryHasNoCode(policy_);
        if (venueRegistry_.code.length == 0) revert RegistryHasNoCode(venueRegistry_);
        if (assetRegistry_.code.length == 0) revert RegistryHasNoCode(assetRegistry_);

        policy = policy_;
        venueRegistry = venueRegistry_;
        assetRegistry = assetRegistry_;
        vaultDeployer = deployers_.vault;
        launchDeployer = deployers_.launch;
        lockerDeployer = deployers_.locker;
        gameDeployer = deployers_.game;
        escrowDeployer = deployers_.escrow;

        _checkDeployer(vaultDeployer);
        _checkDeployer(launchDeployer);
        _checkDeployer(lockerDeployer);
        _checkDeployer(gameDeployer);
        _checkDeployer(escrowDeployer);

        _supported[VAULT] = true;
        _supported[LAUNCH] = true;
        _supported[LOCKER] = true;
        _supported[GAME] = true;
        _supported[ESCROW] = true;

        address canonical = AgenticVaultTemplateDeployer(vaultDeployer)
            .deploy(address(this), venueRegistry_, assetRegistry_, address(this));
        _codehash[VAULT] = canonical.codehash;

        canonical = AgenticLaunchTemplateDeployer(launchDeployer)
            .deploy(address(this), venueRegistry_, assetRegistry_, address(this), address(0), address(0));
        _codehash[LAUNCH] = canonical.codehash;

        canonical = AgenticLockerTemplateDeployer(lockerDeployer)
            .deploy(address(this), venueRegistry_, assetRegistry_, address(this), address(0), uint64(0));
        _codehash[LOCKER] = canonical.codehash;

        canonical = AgenticGameTemplateDeployer(gameDeployer)
            .deploy(address(this), venueRegistry_, assetRegistry_, address(this), address(0));
        _codehash[GAME] = canonical.codehash;

        canonical = AgenticEscrowV2TemplateDeployer(escrowDeployer)
            .deploy(address(this), venueRegistry_, assetRegistry_, address(this), address(0), address(0), address(0));
        _codehash[ESCROW] = canonical.codehash;
    }

    function isSupportedType(bytes32 kind) external view override returns (bool) {
        return _supported[kind];
    }

    function codehashOf(bytes32 kind) external view override returns (bytes32) {
        return _codehash[kind];
    }

    function createFacility(bytes32 kind, bytes calldata initData) external override returns (address facility) {
        if (!_supported[kind]) revert UnsupportedFacilityType(kind);

        if (kind == VAULT) {
            facility = _deployVault(initData);
        } else if (kind == LAUNCH) {
            facility = _deployLaunch(initData);
        } else if (kind == LOCKER) {
            facility = _deployLocker(initData);
        } else if (kind == GAME) {
            facility = _deployGame(initData);
        } else if (kind == ESCROW) {
            facility = _deployEscrow(initData);
        } else {
            revert UnsupportedFacilityType(kind);
        }

        bytes32 expected = _codehash[kind];
        bytes32 actual = facility.codehash;
        if (actual != expected) revert TemplateCodehashMismatch(kind, expected, actual);

        IVenueRegistry(venueRegistry).registerFacility(facility, kind);
        emit FacilityCreated(facility, kind, msg.sender);
    }

    function _deployVault(bytes calldata initData) private returns (address) {
        address owner_ = abi.decode(initData, (address));
        _requireOwner(owner_);
        return AgenticVaultTemplateDeployer(vaultDeployer).deploy(address(this), venueRegistry, assetRegistry, owner_);
    }

    function _deployLaunch(bytes calldata initData) private returns (address) {
        (address owner_, address operator_, address beneficiary_) = abi.decode(initData, (address, address, address));
        _requireOwner(owner_);
        _requireAgentIfSet(beneficiary_);
        return AgenticLaunchTemplateDeployer(launchDeployer)
            .deploy(address(this), venueRegistry, assetRegistry, owner_, operator_, beneficiary_);
    }

    function _deployLocker(bytes calldata initData) private returns (address) {
        (address owner_, address beneficiary_, uint64 unlockTime_) = abi.decode(initData, (address, address, uint64));
        _requireOwner(owner_);
        if (beneficiary_ == address(0)) revert LockerBeneficiaryRequired();
        _requireAgentIfSet(beneficiary_);
        return AgenticLockerTemplateDeployer(lockerDeployer)
            .deploy(address(this), venueRegistry, assetRegistry, owner_, beneficiary_, unlockTime_);
    }

    function _deployGame(bytes calldata initData) private returns (address) {
        (address owner_, address operator_) = abi.decode(initData, (address, address));
        _requireOwner(owner_);
        return AgenticGameTemplateDeployer(gameDeployer)
            .deploy(address(this), venueRegistry, assetRegistry, owner_, operator_);
    }

    function _deployEscrow(bytes calldata initData) private returns (address) {
        (address owner_, address arbiter_, address beneficiary_, address depositor_) =
            abi.decode(initData, (address, address, address, address));
        _requireOwner(owner_);
        if (beneficiary_ == address(0) || depositor_ == address(0)) revert EscrowRolesRequired();
        _requireAgentIfSet(beneficiary_);
        _requireAgentIfSet(depositor_);
        return AgenticEscrowV2TemplateDeployer(escrowDeployer)
            .deploy(address(this), venueRegistry, assetRegistry, owner_, arbiter_, beneficiary_, depositor_);
    }

    function _requireOwner(address owner_) private pure {
        if (owner_ == address(0)) revert InvalidOwner();
    }

    function _requireAgentIfSet(address account) private view {
        if (account == address(0)) return;
        ITransferPolicy transferPolicy = ITransferPolicy(policy);
        if (transferPolicy.categoryOf(account) != FacilityCategory.NONE) revert FacilityNotAgent(account);
        if (!transferPolicy.isMember(account)) revert AgentRequired(account);
    }

    function _checkDeployer(address deployer) private view {
        if (deployer == address(0)) revert ZeroAddress();
        if (deployer.code.length == 0) revert DeployerHasNoCode(deployer);
    }
}

/// @notice Deploys only `AgenticEscrowFacilityV2`.
contract AgenticEscrowV2TemplateDeployer is FacilityTemplateDeployer {
    function deploy(
        address factory_,
        address venueRegistry_,
        address assetRegistry_,
        address owner_,
        address arbiter_,
        address beneficiary_,
        address depositor_
    ) external returns (address) {
        _checkFactory(factory_);
        return address(
            new AgenticEscrowFacilityV2(
                factory_, venueRegistry_, assetRegistry_, owner_, arbiter_, beneficiary_, depositor_
            )
        );
    }
}
