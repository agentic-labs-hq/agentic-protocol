// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssetType, FacilityCategory} from "../common/Types.sol";
import {Governance2Step} from "../common/Governance2Step.sol";
import {IAgentToken} from "../interfaces/IAgentAsset.sol";
import {IAssetRegistry} from "../interfaces/IAssetRegistry.sol";
import {IPolicyRegistry} from "../interfaces/IPolicyRegistry.sol";
import {IVenueRegistry} from "../interfaces/IVenueRegistry.sol";

/// @dev Minimal Uniswap V3 pool surface needed to prove token membership. The
/// V3 core is not vendored in the protocol; the two getters are the standard ABI.
interface IUniswapV3PoolLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

/// @notice Gated asset and pool registry.
/// @dev Assets can only be registered by a governance-enabled registrar whose
/// address is stamped as the token's factory, so no arbitrary contract can be
/// recorded as a gated asset. Pools can only be recorded by the venue
/// registry's POOL registrar (the gated pool factory in the current deployment); the pool must
/// be an active POOL facility and hold the asset as token0 or token1.
contract AgenticAssetRegistry is IAssetRegistry, Governance2Step {
    /// @inheritdoc IAssetRegistry
    address public immutable override policyRegistry;

    /// @inheritdoc IAssetRegistry
    address public immutable override venueRegistry;

    /// @inheritdoc IAssetRegistry
    uint256 public immutable override maxPoolsPerAsset;

    /// @inheritdoc IAssetRegistry
    mapping(address => bool) public override isRegistered;

    /// @inheritdoc IAssetRegistry
    mapping(address => address) public override policyOf;

    /// @inheritdoc IAssetRegistry
    mapping(address => address) public override creatorOf;

    /// @inheritdoc IAssetRegistry
    mapping(address => bool) public override isRegistrar;

    mapping(address => address[]) private _pools;
    mapping(address => mapping(address => bool)) private _poolRecorded;

    /// @notice Thrown when a registry address is zero.
    error ZeroRegistry();
    /// @notice Thrown when a registry address has no code.
    error RegistryHasNoCode(address registry);
    /// @notice Thrown when the pool cap is zero.
    error InvalidMaxPools();
    /// @notice Thrown when the registrar is zero.
    error ZeroRegistrar();
    /// @notice Thrown when a registrar has no code.
    error RegistrarHasNoCode(address account);
    /// @notice Thrown when the caller is not an asset registrar.
    error NotRegistrar(address caller);
    /// @notice Thrown when the asset is zero.
    error ZeroAsset();
    /// @notice Thrown when the asset has no code.
    error AssetHasNoCode(address asset);
    /// @notice Thrown when the asset is already registered.
    error AssetAlreadyRegistered(address asset);
    /// @notice Thrown when the asset's factory stamp differs from the caller.
    error FactoryMismatch(address asset, address expected, address actual);
    /// @notice Thrown when the supplied policy differs from the token's policy.
    error PolicyMismatch(address asset, address expected, address actual);
    /// @notice Thrown when the policy is not registered/allowed.
    error PolicyNotAllowed(address policy);
    /// @notice Thrown when the supplied creator differs from the token's creator.
    error CreatorMismatch(address asset, address expected, address actual);
    /// @notice Thrown when the asset type is not FT.
    error AssetTypeNotSupported(address asset, AssetType actual);
    /// @notice Thrown when the caller is not the venue POOL registrar.
    error NotPoolRegistrar(address caller);
    /// @notice Thrown when the asset is not registered.
    error AssetNotRegistered(address asset);
    /// @notice Thrown when the pool is the zero address.
    error ZeroPool();
    /// @notice Thrown when the pool is not an active POOL facility.
    error PoolNotActive(address pool);
    /// @notice Thrown when the pool already recorded this asset.
    error PoolAlreadyRecorded(address asset, address pool);
    /// @notice Thrown when the per-asset pool cap is reached.
    error PoolCapReached(uint256 maxPoolsPerAsset);
    /// @notice Thrown when the pool does not hold the asset as token0/token1.
    error PoolMissingAsset(address pool, address asset);

    /// @param governance_ Initial two-step governance.
    /// @param policyRegistry_ Versioned policy registry.
    /// @param venueRegistry_ Facility registry used for POOL checks.
    /// @param maxPoolsPerAsset_ Maximum pool records per asset.
    constructor(address governance_, address policyRegistry_, address venueRegistry_, uint256 maxPoolsPerAsset_)
        Governance2Step(governance_)
    {
        if (policyRegistry_ == address(0) || venueRegistry_ == address(0)) revert ZeroRegistry();
        if (policyRegistry_.code.length == 0 || venueRegistry_.code.length == 0) {
            revert RegistryHasNoCode(policyRegistry_.code.length == 0 ? policyRegistry_ : venueRegistry_);
        }
        if (maxPoolsPerAsset_ == 0) revert InvalidMaxPools();

        policyRegistry = policyRegistry_;
        venueRegistry = venueRegistry_;
        maxPoolsPerAsset = maxPoolsPerAsset_;
    }

    /// @inheritdoc IAssetRegistry
    function poolsOf(address asset) external view override returns (address[] memory) {
        return _pools[asset];
    }

    /// @inheritdoc IAssetRegistry
    /// @dev Only a governance-enabled `AgenticAssetRegistry` registrar (the
    /// `AgenticTokenFactory`) may register, and the token's factory stamp must be
    /// that same caller. This binds every record to a real factory deployment.
    function registerAsset(address asset, address policy, address creator) external override {
        if (!isRegistrar[msg.sender]) revert NotRegistrar(msg.sender);
        if (asset == address(0)) revert ZeroAsset();
        if (asset.code.length == 0) revert AssetHasNoCode(asset);
        if (isRegistered[asset]) revert AssetAlreadyRegistered(asset);

        address actualFactory = IAgentToken(asset).factory();
        if (actualFactory != msg.sender) revert FactoryMismatch(asset, msg.sender, actualFactory);

        address actualPolicy = IAgentToken(asset).policy();
        if (actualPolicy != policy) revert PolicyMismatch(asset, policy, actualPolicy);
        if (!IPolicyRegistry(policyRegistry).isPolicyAllowed(policy)) revert PolicyNotAllowed(policy);

        address actualCreator = IAgentToken(asset).creator();
        if (actualCreator != creator) revert CreatorMismatch(asset, creator, actualCreator);

        AssetType actualType = IAgentToken(asset).assetType();
        if (actualType != AssetType.FT) revert AssetTypeNotSupported(asset, actualType);

        isRegistered[asset] = true;
        policyOf[asset] = policy;
        creatorOf[asset] = creator;
        emit AssetRegistered(asset, policy, creator);
    }

    /// @inheritdoc IAssetRegistry
    /// @dev "POOL registrar" is the venue registry's per-category POOL
    /// registrar (the gated pool factory in the current deployment). The recorded pool must be
    /// an active POOL facility and hold the asset as token0 or token1. A pool
    /// may be recorded once per asset, up to `maxPoolsPerAsset`.
    function recordPool(address asset, address pool) external override {
        if (!IVenueRegistry(venueRegistry).isRegistrarFor(msg.sender, FacilityCategory.POOL)) {
            revert NotPoolRegistrar(msg.sender);
        }
        if (!isRegistered[asset]) revert AssetNotRegistered(asset);
        if (pool == address(0)) revert ZeroPool();
        if (!IVenueRegistry(venueRegistry).isFacilityOfCategory(pool, FacilityCategory.POOL)) {
            revert PoolNotActive(pool);
        }
        if (_poolRecorded[asset][pool]) revert PoolAlreadyRecorded(asset, pool);
        if (_pools[asset].length >= maxPoolsPerAsset) revert PoolCapReached(maxPoolsPerAsset);

        address token0 = IUniswapV3PoolLike(pool).token0();
        address token1 = IUniswapV3PoolLike(pool).token1();
        if (token0 != asset && token1 != asset) revert PoolMissingAsset(pool, asset);

        _poolRecorded[asset][pool] = true;
        _pools[asset].push(pool);
        emit PoolRecorded(asset, pool);
    }

    /// @inheritdoc IAssetRegistry
    /// @dev Governance sets the asset registrars (the `AgenticTokenFactory`). A
    /// registrar must be a contract; disabling is allowed but still requires code.
    function setRegistrar(address account, bool enabled) external override onlyGovernance {
        if (account == address(0)) revert ZeroRegistrar();
        if (account.code.length == 0) revert RegistrarHasNoCode(account);
        isRegistrar[account] = enabled;
        emit RegistrarSet(account, enabled);
    }
}
