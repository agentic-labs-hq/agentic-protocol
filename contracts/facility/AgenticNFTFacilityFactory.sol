// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FacilityCategory, NFT_ESCROW, NFT_GAME, NFT_LAUNCH, NFT_LOCKER, NFT_VAULT} from "../common/Types.sol";
import {IFacilityFactory} from "../interfaces/IFacilityFactory.sol";
import {ITransferPolicy} from "../interfaces/ITransferPolicy.sol";
import {IVenueRegistry} from "../interfaces/IVenueRegistry.sol";

import {AgenticNFTEscrowFacility} from "./AgenticNFTEscrowFacility.sol";
import {AgenticNFTGameFacility} from "./AgenticNFTGameFacility.sol";
import {AgenticNFTLaunchFacility} from "./AgenticNFTLaunchFacility.sol";
import {AgenticNFTLockerFacility} from "./AgenticNFTLockerFacility.sol";
import {AgenticNFTVaultFacility} from "./AgenticNFTVaultFacility.sol";

/// @notice Permissionless NFT facility factory (INTERFACES v2.3 §NFT).
/// @dev Mirrors `AgenticFacilityFactoryV2`: it deploys only the five audited NFT
/// templates; there is no proxy, arbitrary template, upgrade, admin review or
/// token custody. Owner/roles are storage in the templates, so every facility
/// of a kind from this factory has the same runtime codehash. `codehashOf(kind)`
/// is the runtime codehash of a canonical deployment made in the constructor,
/// and every new deployment is checked against it before registration.
///
/// Template creation code lives in one deployment helper per kind (defined
/// below). A helper accepts only the factory that calls it
/// (`msg.sender == factory_`), so a third party cannot stamp a deployment with
/// this factory's address; a template deployed directly is not registered and
/// is inert under the venue policy.
///
/// `policy()` is the canonical transfer policy used only to validate
/// agent-only beneficiary roles. Per-collection policies still gate every
/// actual transfer. `nftRegistry()` classifies gated collections; unregistered
/// collections have no recipient restriction in the facilities.
///
/// `initData` encodings (opaque in the frozen interface; fixed here):
/// - NFT_VAULT: `abi.encode(address owner)`
/// - NFT_LAUNCH: `abi.encode(address owner, address operator, address beneficiary)`
/// - NFT_LOCKER: `abi.encode(address owner, address beneficiary, uint64 unlockTime)`
/// - NFT_GAME: `abi.encode(address owner, address operator)`
/// - NFT_ESCROW: `abi.encode(address owner, address arbiter, address beneficiary)`
///
/// Optional roles may be zero and set later by the owner. Agent beneficiaries
/// are validated when non-zero; a zero beneficiary can be set later.
contract AgenticNFTFacilityFactory is IFacilityFactory {
    /// @notice Deployment helper addresses for each supported kind.
    struct TemplateDeployers {
        address vault;
        address launch;
        address locker;
        address game;
        address escrow;
    }

    /// @inheritdoc IFacilityFactory
    address public immutable override policy;

    /// @notice Venue registry used for `registerFacility` and migration checks.
    address public immutable venueRegistry;

    /// @notice Gated NFT registry used by facilities to classify collections.
    address public immutable nftRegistry;

    address public immutable vaultDeployer;
    address public immutable launchDeployer;
    address public immutable lockerDeployer;
    address public immutable gameDeployer;
    address public immutable escrowDeployer;

    mapping(bytes32 => bool) private _supported;
    mapping(bytes32 => bytes32) private _codehash;

    /// @notice Thrown when a registry/policy argument or deployer is zero.
    error ZeroAddress();
    /// @notice Thrown when a configured registry/policy has no code.
    error RegistryHasNoCode(address account);
    /// @notice Thrown when a configured template deployer has no code.
    error DeployerHasNoCode(address account);
    /// @notice Thrown for a kind this factory does not deploy.
    error UnsupportedFacilityType(bytes32 kind);
    /// @notice Thrown when the owner in `initData` is zero.
    error InvalidOwner();
    /// @notice Thrown when an agent-only beneficiary is not an agent.
    error AgentRequired(address account);
    /// @notice Thrown when an agent-only beneficiary is a facility.
    error FacilityNotAgent(address account);
    /// @notice Thrown when a deployment does not match the canonical codehash.
    error TemplateCodehashMismatch(bytes32 kind, bytes32 expected, bytes32 actual);
    /// @notice Thrown when a LOCKER is created without a beneficiary.
    error LockerBeneficiaryRequired();
    /// @notice Thrown when the venue registry maps the kind to another category.
    error UnexpectedFacilityCategory(bytes32 kind, FacilityCategory expected, FacilityCategory actual);

    /// @param policy_ Canonical `ITransferPolicy` for agent-role validation.
    /// @param venueRegistry_ Venue registry; the factory must be configured as a
    /// CUSTODY/PURPOSE registrar at deployment/test setup.
    /// @param nftRegistry_ NFT registry used by facility templates to classify
    /// gated collections.
    /// @param deployers_ One fixed-template deployment helper per supported kind.
    constructor(address policy_, address venueRegistry_, address nftRegistry_, TemplateDeployers memory deployers_) {
        if (policy_ == address(0) || venueRegistry_ == address(0) || nftRegistry_ == address(0)) {
            revert ZeroAddress();
        }
        if (policy_.code.length == 0) revert RegistryHasNoCode(policy_);
        if (venueRegistry_.code.length == 0) revert RegistryHasNoCode(venueRegistry_);
        if (nftRegistry_.code.length == 0) revert RegistryHasNoCode(nftRegistry_);

        policy = policy_;
        venueRegistry = venueRegistry_;
        nftRegistry = nftRegistry_;
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

        _supported[NFT_VAULT] = true;
        _supported[NFT_LAUNCH] = true;
        _supported[NFT_LOCKER] = true;
        _supported[NFT_GAME] = true;
        _supported[NFT_ESCROW] = true;

        // Deploy one canonical instance per kind. These are never registered
        // and never hold assets; their only purpose is the audited runtime
        // codehash, including the factory/type immutables. All constructor
        // arguments are storage, so every same-kind deployment is identical.
        address canonical = AgenticNFTVaultTemplateDeployer(vaultDeployer)
            .deploy(address(this), venueRegistry_, nftRegistry_, address(this));
        _codehash[NFT_VAULT] = canonical.codehash;

        canonical = AgenticNFTLaunchTemplateDeployer(launchDeployer)
            .deploy(address(this), venueRegistry_, nftRegistry_, address(this), address(0), address(0));
        _codehash[NFT_LAUNCH] = canonical.codehash;

        canonical = AgenticNFTLockerTemplateDeployer(lockerDeployer)
            .deploy(address(this), venueRegistry_, nftRegistry_, address(this), address(0), uint64(0));
        _codehash[NFT_LOCKER] = canonical.codehash;

        canonical = AgenticNFTGameTemplateDeployer(gameDeployer)
            .deploy(address(this), venueRegistry_, nftRegistry_, address(this), address(0));
        _codehash[NFT_GAME] = canonical.codehash;

        canonical = AgenticNFTEscrowTemplateDeployer(escrowDeployer)
            .deploy(address(this), venueRegistry_, nftRegistry_, address(this), address(0), address(0));
        _codehash[NFT_ESCROW] = canonical.codehash;
    }

    /// @inheritdoc IFacilityFactory
    function isSupportedType(bytes32 kind) external view override returns (bool) {
        return _supported[kind];
    }

    /// @inheritdoc IFacilityFactory
    function codehashOf(bytes32 kind) external view override returns (bytes32) {
        return _codehash[kind];
    }

    /// @inheritdoc IFacilityFactory
    /// @dev Permissionless. Decodes the kind-specific role assignment, validates
    /// owner/agent-only roles against the canonical policy, deploys only the
    /// matching template, verifies the canonical codehash, and registers the
    /// facility with `venueRegistry`. Any failure reverts the whole creation.
    function createFacility(bytes32 kind, bytes calldata initData) external override returns (address facility) {
        if (!_supported[kind]) revert UnsupportedFacilityType(kind);

        if (kind == NFT_VAULT) {
            facility = _deployVault(initData);
        } else if (kind == NFT_LAUNCH) {
            facility = _deployLaunch(initData);
        } else if (kind == NFT_LOCKER) {
            facility = _deployLocker(initData);
        } else if (kind == NFT_GAME) {
            facility = _deployGame(initData);
        } else if (kind == NFT_ESCROW) {
            facility = _deployEscrow(initData);
        } else {
            revert UnsupportedFacilityType(kind);
        }

        bytes32 expected = _codehash[kind];
        bytes32 actual = facility.codehash;
        if (actual != expected) revert TemplateCodehashMismatch(kind, expected, actual);

        IVenueRegistry(venueRegistry).registerFacility(facility, kind);
        FacilityCategory expectedCategory = _categoryOf(kind);
        FacilityCategory actualCategory = IVenueRegistry(venueRegistry).facilityCategory(facility);
        if (actualCategory != expectedCategory) {
            revert UnexpectedFacilityCategory(kind, expectedCategory, actualCategory);
        }
        // The event is emitted only after registration succeeds; a revert
        // above rolls it back.
        // forge-lint: disable-next-line(reentrancy-events)
        emit FacilityCreated(facility, kind, msg.sender);
    }

    function _deployVault(bytes calldata initData) private returns (address) {
        address owner_ = abi.decode(initData, (address));
        _requireOwner(owner_);
        return AgenticNFTVaultTemplateDeployer(vaultDeployer).deploy(address(this), venueRegistry, nftRegistry, owner_);
    }

    function _deployLaunch(bytes calldata initData) private returns (address) {
        (address owner_, address operator_, address beneficiary_) = abi.decode(initData, (address, address, address));
        _requireOwner(owner_);
        _requireAgentIfSet(beneficiary_);
        return AgenticNFTLaunchTemplateDeployer(launchDeployer)
            .deploy(address(this), venueRegistry, nftRegistry, owner_, operator_, beneficiary_);
    }

    function _deployLocker(bytes calldata initData) private returns (address) {
        (address owner_, address beneficiary_, uint64 unlockTime_) = abi.decode(initData, (address, address, uint64));
        _requireOwner(owner_);
        if (beneficiary_ == address(0)) revert LockerBeneficiaryRequired();
        _requireAgentIfSet(beneficiary_);
        return AgenticNFTLockerTemplateDeployer(lockerDeployer)
            .deploy(address(this), venueRegistry, nftRegistry, owner_, beneficiary_, unlockTime_);
    }

    function _deployGame(bytes calldata initData) private returns (address) {
        (address owner_, address operator_) = abi.decode(initData, (address, address));
        _requireOwner(owner_);
        return AgenticNFTGameTemplateDeployer(gameDeployer)
            .deploy(address(this), venueRegistry, nftRegistry, owner_, operator_);
    }

    function _deployEscrow(bytes calldata initData) private returns (address) {
        (address owner_, address arbiter_, address beneficiary_) = abi.decode(initData, (address, address, address));
        _requireOwner(owner_);
        _requireAgentIfSet(beneficiary_);
        return AgenticNFTEscrowTemplateDeployer(escrowDeployer)
            .deploy(address(this), venueRegistry, nftRegistry, owner_, arbiter_, beneficiary_);
    }

    function _requireOwner(address owner_) private pure {
        if (owner_ == address(0)) revert InvalidOwner();
    }

    /// @dev Zero means "unset, owner sets later"; non-zero must be an agent and
    /// must not be a facility (no facility beneficiary).
    function _requireAgentIfSet(address account) private view {
        if (account == address(0)) return;
        ITransferPolicy transferPolicy = ITransferPolicy(policy);
        // `categoryOf` persists after revoke; a revoked facility is still a
        // facility and cannot hold an agent-only role.
        if (transferPolicy.categoryOf(account) != FacilityCategory.NONE) revert FacilityNotAgent(account);
        if (!transferPolicy.isMember(account)) revert AgentRequired(account);
    }

    /// @dev Expected venue category for each supported kind.
    function _categoryOf(bytes32 kind) private pure returns (FacilityCategory) {
        if (kind == NFT_VAULT || kind == NFT_LAUNCH || kind == NFT_LOCKER) {
            return FacilityCategory.CUSTODY;
        }
        return FacilityCategory.PURPOSE;
    }

    function _checkDeployer(address deployer) private view {
        if (deployer == address(0)) revert ZeroAddress();
        if (deployer.code.length == 0) revert DeployerHasNoCode(deployer);
    }
}

/// @notice Fixed-template deployment helpers. See the factory NatSpec for why
/// the creation code is split out of `AgenticNFTFacilityFactory`.
abstract contract FacilityTemplateDeployer {
    error NotFactory(address caller);

    function _checkFactory(address factory_) internal view {
        if (msg.sender != factory_) revert NotFactory(msg.sender);
    }
}

/// @notice Deploys only `AgenticNFTVaultFacility`.
contract AgenticNFTVaultTemplateDeployer is FacilityTemplateDeployer {
    function deploy(address factory_, address venueRegistry_, address nftRegistry_, address owner_)
        external
        returns (address)
    {
        _checkFactory(factory_);
        return address(new AgenticNFTVaultFacility(factory_, venueRegistry_, nftRegistry_, owner_));
    }
}

/// @notice Deploys only `AgenticNFTLaunchFacility`.
contract AgenticNFTLaunchTemplateDeployer is FacilityTemplateDeployer {
    function deploy(
        address factory_,
        address venueRegistry_,
        address nftRegistry_,
        address owner_,
        address operator_,
        address beneficiary_
    ) external returns (address) {
        _checkFactory(factory_);
        return
            address(
                new AgenticNFTLaunchFacility(factory_, venueRegistry_, nftRegistry_, owner_, operator_, beneficiary_)
            );
    }
}

/// @notice Deploys only `AgenticNFTLockerFacility`.
contract AgenticNFTLockerTemplateDeployer is FacilityTemplateDeployer {
    function deploy(
        address factory_,
        address venueRegistry_,
        address nftRegistry_,
        address owner_,
        address beneficiary_,
        uint64 unlockTime_
    ) external returns (address) {
        _checkFactory(factory_);
        return address(
            new AgenticNFTLockerFacility(factory_, venueRegistry_, nftRegistry_, owner_, beneficiary_, unlockTime_)
        );
    }
}

/// @notice Deploys only `AgenticNFTGameFacility`.
contract AgenticNFTGameTemplateDeployer is FacilityTemplateDeployer {
    function deploy(address factory_, address venueRegistry_, address nftRegistry_, address owner_, address operator_)
        external
        returns (address)
    {
        _checkFactory(factory_);
        return address(new AgenticNFTGameFacility(factory_, venueRegistry_, nftRegistry_, owner_, operator_));
    }
}

/// @notice Deploys only `AgenticNFTEscrowFacility`.
contract AgenticNFTEscrowTemplateDeployer is FacilityTemplateDeployer {
    function deploy(
        address factory_,
        address venueRegistry_,
        address nftRegistry_,
        address owner_,
        address arbiter_,
        address beneficiary_
    ) external returns (address) {
        _checkFactory(factory_);
        return
            address(
                new AgenticNFTEscrowFacility(factory_, venueRegistry_, nftRegistry_, owner_, arbiter_, beneficiary_)
            );
    }
}
