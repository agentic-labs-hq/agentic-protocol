// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ESCROW, FacilityCategory, GAME, LAUNCH, LENDING, LOCKER, VAULT} from "../common/Types.sol";
import {IFacilityFactory} from "../interfaces/IFacilityFactory.sol";
import {ITransferPolicy} from "../interfaces/ITransferPolicy.sol";
import {IVenueRegistry} from "../interfaces/IVenueRegistry.sol";

import {AgenticEscrowFacility} from "./AgenticEscrowFacility.sol";
import {AgenticGameFacility} from "./AgenticGameFacility.sol";
import {AgenticLaunchFacility} from "./AgenticLaunchFacility.sol";
import {AgenticLendingFacility} from "./AgenticLendingFacility.sol";
import {AgenticLockerFacility} from "./AgenticLockerFacility.sol";
import {AgenticVaultFacility} from "./AgenticVaultFacility.sol";

/// @notice Permissionless standard facility factory.
/// @dev Deploys only the six canonical CUSTODY/PURPOSE templates; there is no
/// proxy, arbitrary template, upgrade, admin review or token custody. The
/// owner/roles are storage in the templates, so every facility of a kind from
/// this factory has the same runtime codehash. `codehashOf(kind)` is the
/// runtime codehash of a canonical deployment made by this factory in its
/// constructor, and every new deployment is checked against it before the
/// facility is registered.
///
/// Template creation code lives in one deployment helper per kind (defined
/// below). Passing their addresses keeps `AgenticFacilityFactory`'s runtime below the
/// EIP-170 limit while the helpers deploy only the fixed templates. A helper
/// accepts only the factory that calls it (`msg.sender == factory_`), so a third
/// party cannot stamp a deployment with this factory's address; a template
/// deployed directly (outside a factory helper) is not registered and is inert
/// under the venue policy.
///
/// `policy()` is the canonical transfer policy used only to validate
/// agent-only roles/beneficiaries. Per-token policies still gate every actual
/// transfer. `assetRegistry()` classifies gated tokens; VAULT/LAUNCH treat
/// unregistered tokens as public ERC20 with owner-only release paths.
///
/// `initData` encodings (opaque in the public interface; fixed here):
/// - VAULT: `abi.encode(address owner)`
/// - LAUNCH: `abi.encode(address owner, address operator, address beneficiary)`
/// - LOCKER: `abi.encode(address owner, address beneficiary, uint64 unlockTime)`
/// - GAME: `abi.encode(address owner, address operator)`
/// - ESCROW: `abi.encode(address owner, address arbiter, address beneficiary, address depositor)`
/// - LENDING: `abi.encode(address owner, address keeper, address oracle, address lender, address borrower)`
///
/// Optional roles may be zero and set later by the owner. Agent beneficiaries/
/// depositors/lenders/borrowers are validated when non-zero; a zero depositor/
/// lender/borrower is fixed by the first deposit/borrow in the template.
contract AgenticFacilityFactory is IFacilityFactory {
    /// @notice Deployment helper addresses for each supported kind.
    struct TemplateDeployers {
        address vault;
        address launch;
        address locker;
        address game;
        address escrow;
        address lending;
    }

    /// @inheritdoc IFacilityFactory
    address public immutable override policy;

    /// @notice Venue registry used for `registerFacility` and migration checks.
    address public immutable venueRegistry;

    /// @notice Asset registry used by facilities to classify gated vs public ERC20.
    address public immutable assetRegistry;

    address public immutable vaultDeployer;
    address public immutable launchDeployer;
    address public immutable lockerDeployer;
    address public immutable gameDeployer;
    address public immutable escrowDeployer;
    address public immutable lendingDeployer;

    mapping(bytes32 => bool) private _supported;
    mapping(bytes32 => bytes32) private _codehash;

    /// @notice Thrown when a registry/policy argument is zero.
    error ZeroAddress();
    /// @notice Thrown when a configured registry/policy has no code.
    error RegistryHasNoCode(address account);
    /// @notice Thrown when a configured template deployer has no code.
    error DeployerHasNoCode(address account);
    /// @notice Thrown for a kind this factory does not deploy.
    error UnsupportedFacilityType(bytes32 kind);
    /// @notice Thrown when the owner in `initData` is zero.
    error InvalidOwner();
    /// @notice Thrown when an agent-only role is not an agent.
    error AgentRequired(address account);
    /// @notice Thrown when an agent-only role is a facility.
    error FacilityNotAgent(address account);
    /// @notice Thrown when a deployment does not match the canonical codehash.
    error TemplateCodehashMismatch(bytes32 kind, bytes32 expected, bytes32 actual);

    /// @param policy_ Canonical `ITransferPolicy` for agent-role validation.
    /// @param venueRegistry_ Venue registry; the factory must be configured as a
    /// CUSTODY/PURPOSE registrar at deployment/test setup.
    /// @param assetRegistry_ Asset registry used by facility templates to
    /// distinguish gated tokens from public ERC20.
    /// @param deployers_ One fixed-template deployment helper per supported kind.
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
        lendingDeployer = deployers_.lending;

        _checkDeployer(vaultDeployer);
        _checkDeployer(launchDeployer);
        _checkDeployer(lockerDeployer);
        _checkDeployer(gameDeployer);
        _checkDeployer(escrowDeployer);
        _checkDeployer(lendingDeployer);

        _supported[VAULT] = true;
        _supported[LAUNCH] = true;
        _supported[LOCKER] = true;
        _supported[GAME] = true;
        _supported[ESCROW] = true;
        _supported[LENDING] = true;

        // Deploy one canonical instance per kind. These are never registered
        // and never hold assets; their only purpose is the canonical runtime
        // codehash, including the factory/type immutables. All constructor
        // arguments are storage, so every same-kind deployment is identical.
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

        canonical = AgenticEscrowTemplateDeployer(escrowDeployer)
            .deploy(address(this), venueRegistry_, assetRegistry_, address(this), address(0), address(0), address(0));
        _codehash[ESCROW] = canonical.codehash;

        canonical = AgenticLendingTemplateDeployer(lendingDeployer)
            .deploy(
                address(this),
                venueRegistry_,
                assetRegistry_,
                address(this),
                address(0),
                address(0),
                address(0),
                address(0)
            );
        _codehash[LENDING] = canonical.codehash;
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
        } else if (kind == LENDING) {
            facility = _deployLending(initData);
        } else {
            revert UnsupportedFacilityType(kind);
        }

        bytes32 expected = _codehash[kind];
        bytes32 actual = facility.codehash;
        if (actual != expected) revert TemplateCodehashMismatch(kind, expected, actual);

        IVenueRegistry(venueRegistry).registerFacility(facility, kind);
        // The event is emitted only after registration succeeds; a revert
        // above rolls it back.
        // forge-lint: disable-next-line(reentrancy-events)
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
        _requireAgentIfSet(beneficiary_);
        _requireAgentIfSet(depositor_);
        return AgenticEscrowTemplateDeployer(escrowDeployer)
            .deploy(address(this), venueRegistry, assetRegistry, owner_, arbiter_, beneficiary_, depositor_);
    }

    function _deployLending(bytes calldata initData) private returns (address) {
        (address owner_, address keeper_, address oracle_, address lender_, address borrower_) =
            abi.decode(initData, (address, address, address, address, address));
        _requireOwner(owner_);
        _requireAgentIfSet(lender_);
        _requireAgentIfSet(borrower_);
        return AgenticLendingTemplateDeployer(lendingDeployer)
            .deploy(address(this), venueRegistry, assetRegistry, owner_, keeper_, oracle_, lender_, borrower_);
    }

    function _requireOwner(address owner_) private pure {
        if (owner_ == address(0)) revert InvalidOwner();
    }

    /// @dev Zero means "unset, owner sets later"; non-zero must be an agent and
    /// must not be a facility (no facility beneficiary/depositor/borrower).
    function _requireAgentIfSet(address account) private view {
        if (account == address(0)) return;
        ITransferPolicy transferPolicy = ITransferPolicy(policy);
        // `categoryOf` persists after revoke; a revoked facility is still a
        // facility and cannot hold an agent-only role.
        if (transferPolicy.categoryOf(account) != FacilityCategory.NONE) revert FacilityNotAgent(account);
        if (!transferPolicy.isMember(account)) revert AgentRequired(account);
    }

    function _checkDeployer(address deployer) private view {
        if (deployer == address(0)) revert ZeroAddress();
        if (deployer.code.length == 0) revert DeployerHasNoCode(deployer);
    }
}

/// @notice Fixed-template deployment helpers. See the factory NatSpec for why
/// the creation code is split out of `AgenticFacilityFactory`.
abstract contract FacilityTemplateDeployer {
    error NotFactory(address caller);

    function _checkFactory(address factory_) internal view {
        if (msg.sender != factory_) revert NotFactory(msg.sender);
    }
}

/// @notice Deploys only `AgenticVaultFacility`.
contract AgenticVaultTemplateDeployer is FacilityTemplateDeployer {
    function deploy(address factory_, address venueRegistry_, address assetRegistry_, address owner_)
        external
        returns (address)
    {
        _checkFactory(factory_);
        return address(new AgenticVaultFacility(factory_, venueRegistry_, assetRegistry_, owner_));
    }
}

/// @notice Deploys only `AgenticLaunchFacility`.
contract AgenticLaunchTemplateDeployer is FacilityTemplateDeployer {
    function deploy(
        address factory_,
        address venueRegistry_,
        address assetRegistry_,
        address owner_,
        address operator_,
        address beneficiary_
    ) external returns (address) {
        _checkFactory(factory_);
        return
            address(
                new AgenticLaunchFacility(factory_, venueRegistry_, assetRegistry_, owner_, operator_, beneficiary_)
            );
    }
}

/// @notice Deploys only `AgenticLockerFacility`.
contract AgenticLockerTemplateDeployer is FacilityTemplateDeployer {
    function deploy(
        address factory_,
        address venueRegistry_,
        address assetRegistry_,
        address owner_,
        address beneficiary_,
        uint64 unlockTime_
    ) external returns (address) {
        _checkFactory(factory_);
        return
            address(
                new AgenticLockerFacility(factory_, venueRegistry_, assetRegistry_, owner_, beneficiary_, unlockTime_)
            );
    }
}

/// @notice Deploys only `AgenticGameFacility`.
contract AgenticGameTemplateDeployer is FacilityTemplateDeployer {
    function deploy(address factory_, address venueRegistry_, address assetRegistry_, address owner_, address operator_)
        external
        returns (address)
    {
        _checkFactory(factory_);
        return address(new AgenticGameFacility(factory_, venueRegistry_, assetRegistry_, owner_, operator_));
    }
}

/// @notice Deploys only `AgenticEscrowFacility`.
contract AgenticEscrowTemplateDeployer is FacilityTemplateDeployer {
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
            new AgenticEscrowFacility(
                factory_, venueRegistry_, assetRegistry_, owner_, arbiter_, beneficiary_, depositor_
            )
        );
    }
}

/// @notice Deploys only `AgenticLendingFacility`.
contract AgenticLendingTemplateDeployer is FacilityTemplateDeployer {
    function deploy(
        address factory_,
        address venueRegistry_,
        address assetRegistry_,
        address owner_,
        address keeper_,
        address oracle_,
        address lender_,
        address borrower_
    ) external returns (address) {
        _checkFactory(factory_);
        return address(
            new AgenticLendingFacility(
                factory_, venueRegistry_, assetRegistry_, owner_, keeper_, oracle_, lender_, borrower_
            )
        );
    }
}
