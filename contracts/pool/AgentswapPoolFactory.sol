// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FacilityCategory, POOL} from "../common/Types.sol";
import {Governance2Step} from "../common/Governance2Step.sol";
import {IAssetRegistry} from "../interfaces/IAssetRegistry.sol";
import {IGatedPoolFactory} from "../interfaces/IGatedPoolFactory.sol";
import {IQuoteAssetRegistry} from "../interfaces/IQuoteAssetRegistry.sol";
import {IVenueRegistry} from "../interfaces/IVenueRegistry.sol";

import {IV3FactoryLike} from "./interfaces/IV3FactoryLike.sol";
import {IV3PoolLike} from "./interfaces/IV3PoolLike.sol";

/// @notice Gated Uniswap V3 pool factory.
/// @dev 0.8.20 wrapper over the pinned 0.7.6 V3 core factory. The wrapper owns
/// the canonical factory, deploys and initializes pools at the creator's
/// `sqrtPriceX96`, sets the protocol fee to `(8,8)`, and registers every pool
/// as a `POOL` facility. Pool creation is creator-authorized but gated: the
/// caller must be the creator of every gated side, at least one side must be a
/// registered gated asset, and every non-gated side must be an approved quote
/// asset, so no public-public pool can be created.
///
/// There is no proxy, no setter for the canonical factory, no arbitrary call
/// and no arbitrary recipient: `collectProtocol` always pays `treasury()`.
/// Deployment must transfer canonical factory ownership to this contract; every
/// privileged pool operation re-checks it where needed.
contract AgentswapPoolFactory is IGatedPoolFactory, Governance2Step {
    /// @notice Protocol fee applied to both pool sides on creation (1/8 each).
    uint8 private constant PROTOCOL_FEE = 8;

    /// @dev Uniswap V3 `TickMath.MIN_SQRT_RATIO` (inclusive lower bound).
    uint160 private constant MIN_SQRT_RATIO = 4295128739;

    /// @dev Uniswap V3 `TickMath.MAX_SQRT_RATIO` (exclusive upper bound).
    uint160 private constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    /// @inheritdoc IGatedPoolFactory
    address public immutable override canonicalFactory;

    /// @inheritdoc IGatedPoolFactory
    address public immutable override assetRegistry;

    /// @inheritdoc IGatedPoolFactory
    address public immutable override quoteAssetRegistry;

    /// @inheritdoc IGatedPoolFactory
    address public immutable override venueRegistry;

    /// @inheritdoc IGatedPoolFactory
    address public immutable override policyRegistry;

    /// @inheritdoc IGatedPoolFactory
    address public override treasury;

    /// @notice Thrown when the canonical factory address is zero.
    error ZeroCanonicalFactory();
    /// @notice Thrown when the canonical factory has no code.
    error CanonicalFactoryHasNoCode(address canonicalFactory);
    /// @notice Thrown when a registry address is zero.
    error ZeroRegistry();
    /// @notice Thrown when a configured registry has no code.
    error RegistryHasNoCode(address registry);
    /// @notice Thrown when the treasury address is zero.
    error ZeroTreasury();
    /// @notice Thrown when the treasury has no code.
    error TreasuryHasNoCode(address treasury);
    /// @notice Thrown when the account is not an active `FEE_RECIPIENT`.
    error NotActiveFeeRecipient(address account);
    /// @notice Thrown when a pool token is the zero address.
    error ZeroToken();
    /// @notice Thrown when both pool tokens are the same address.
    error IdenticalTokens(address token);
    /// @notice Thrown when the canonical factory has no tick spacing for `fee`.
    error FeeNotAllowed(uint24 fee);
    /// @notice Thrown when neither pool token is a registered gated asset.
    error NoGatedAsset();
    /// @notice Thrown when a non-gated pool token is not an approved quote asset.
    error NotQuoteAsset(address token);
    /// @notice Thrown when the caller is not the creator of a gated asset.
    error NotAssetCreator(address asset, address caller);
    /// @notice Thrown when this wrapper is not the canonical factory owner.
    error NotCanonicalFactoryOwner(address actualOwner, address expectedOwner);
    /// @notice Thrown when `sqrtPriceX96` is outside the V3 valid range.
    error InvalidSqrtPrice(uint160 sqrtPriceX96);
    /// @notice Thrown when a pool address is zero or codeless.
    error InvalidPool(address pool);
    /// @notice Thrown when the new canonical factory owner is zero.
    error ZeroNewOwner();
    /// @notice Thrown when a protocol fee is neither zero nor in `[4,10]`.
    error InvalidProtocolFee(uint8 feeProtocol);

    /// @param canonicalFactory_ Pinned V3 core factory owned by this wrapper.
    /// @param assetRegistry_ Gated asset registry.
    /// @param quoteAssetRegistry_ Governance-managed quote-asset allowlist.
    /// @param venueRegistry_ Facility registry; this wrapper must become the
    /// `POOL` registrar after deployment.
    /// @param policyRegistry_ Versioned transfer-policy registry (exposed for
    /// deployment tooling; the factory does not resolve policies itself).
    /// @param treasury_ Active `FEE_RECIPIENT` receiving collected protocol fees.
    /// @param governance_ Initial two-step governance.
    constructor(
        address canonicalFactory_,
        address assetRegistry_,
        address quoteAssetRegistry_,
        address venueRegistry_,
        address policyRegistry_,
        address treasury_,
        address governance_
    ) Governance2Step(governance_) {
        if (canonicalFactory_ == address(0)) revert ZeroCanonicalFactory();
        if (canonicalFactory_.code.length == 0) revert CanonicalFactoryHasNoCode(canonicalFactory_);

        if (
            assetRegistry_ == address(0) || quoteAssetRegistry_ == address(0) || venueRegistry_ == address(0)
                || policyRegistry_ == address(0)
        ) revert ZeroRegistry();
        if (assetRegistry_.code.length == 0) revert RegistryHasNoCode(assetRegistry_);
        if (quoteAssetRegistry_.code.length == 0) revert RegistryHasNoCode(quoteAssetRegistry_);
        if (venueRegistry_.code.length == 0) revert RegistryHasNoCode(venueRegistry_);
        if (policyRegistry_.code.length == 0) revert RegistryHasNoCode(policyRegistry_);

        if (treasury_ == address(0)) revert ZeroTreasury();
        if (treasury_.code.length == 0) revert TreasuryHasNoCode(treasury_);
        if (!IVenueRegistry(venueRegistry_).isFacilityOfCategory(treasury_, FacilityCategory.FEE_RECIPIENT)) {
            revert NotActiveFeeRecipient(treasury_);
        }

        canonicalFactory = canonicalFactory_;
        assetRegistry = assetRegistry_;
        quoteAssetRegistry = quoteAssetRegistry_;
        venueRegistry = venueRegistry_;
        policyRegistry = policyRegistry_;
        treasury = treasury_;
    }

    /// @inheritdoc IGatedPoolFactory
    /// @dev Creator-authorized and atomic: only the creator of every gated side
    /// may create the pool. This prevents an unrelated account from consuming
    /// the per-asset pool-record cap or front-running a project's official
    /// pool with junk gated pairs. Validate the tokens/fee/sqrt price, create
    /// the canonical pool, initialize it at the creator's start price, set
    /// `(8,8)`, register it as a `POOL` facility and record it for every gated
    /// side. Any failure reverts pool creation and registration together. The
    /// wrapper must be the canonical factory owner so the protocol-fee calls on
    /// the new pool succeed.
    function createPool(address tokenA, address tokenB, uint24 fee, uint160 sqrtPriceX96)
        external
        override
        returns (address pool)
    {
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroToken();
        if (tokenA == tokenB) revert IdenticalTokens(tokenA);
        if (!isAllowedFee(fee)) revert FeeNotAllowed(fee);

        bool gatedA = IAssetRegistry(assetRegistry).isRegistered(tokenA);
        bool gatedB = IAssetRegistry(assetRegistry).isRegistered(tokenB);
        if (!gatedA && !gatedB) revert NoGatedAsset();
        if (gatedA && IAssetRegistry(assetRegistry).creatorOf(tokenA) != msg.sender) {
            revert NotAssetCreator(tokenA, msg.sender);
        }
        if (gatedB && IAssetRegistry(assetRegistry).creatorOf(tokenB) != msg.sender) {
            revert NotAssetCreator(tokenB, msg.sender);
        }
        if (!gatedA && !IQuoteAssetRegistry(quoteAssetRegistry).isQuoteAsset(tokenA)) revert NotQuoteAsset(tokenA);
        if (!gatedB && !IQuoteAssetRegistry(quoteAssetRegistry).isQuoteAsset(tokenB)) revert NotQuoteAsset(tokenB);

        _requireCanonicalOwner();
        _validateSqrtPrice(sqrtPriceX96);

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        pool = IV3FactoryLike(canonicalFactory).createPool(tokenA, tokenB, fee);
        IV3PoolLike(pool).initialize(sqrtPriceX96);
        IV3PoolLike(pool).setFeeProtocol(PROTOCOL_FEE, PROTOCOL_FEE);

        IVenueRegistry(venueRegistry).registerFacility(pool, POOL);
        if (gatedA) IAssetRegistry(assetRegistry).recordPool(tokenA, pool);
        if (gatedB) IAssetRegistry(assetRegistry).recordPool(tokenB, pool);

        emit GatedPoolCreated(pool, token0, token1, fee, sqrtPriceX96);
    }

    /// @inheritdoc IGatedPoolFactory
    /// @dev Governance-only. Each side must be either disabled (`0`) or in the
    /// V3 range `[4,10]`. The canonical pool re-checks the bound and ownership.
    function setProtocolFee(address pool, uint8 feeProtocol0, uint8 feeProtocol1) external override onlyGovernance {
        if (pool == address(0) || pool.code.length == 0) revert InvalidPool(pool);
        _validateFeeProtocol(feeProtocol0);
        _validateFeeProtocol(feeProtocol1);

        IV3PoolLike(pool).setFeeProtocol(feeProtocol0, feeProtocol1);
        emit ProtocolFeeSet(pool, feeProtocol0, feeProtocol1);
    }

    /// @inheritdoc IGatedPoolFactory
    /// @dev Governance-only. The recipient is always `treasury()`; there is no
    /// recipient parameter and no arbitrary transfer path.
    function collectProtocol(address pool, uint128 amount0Requested, uint128 amount1Requested)
        external
        override
        onlyGovernance
        returns (uint128 amount0, uint128 amount1)
    {
        if (pool == address(0) || pool.code.length == 0) revert InvalidPool(pool);
        address recipient = treasury;
        (amount0, amount1) = IV3PoolLike(pool).collectProtocol(recipient, amount0Requested, amount1Requested);
        emit ProtocolCollected(pool, recipient, amount0, amount1);
    }

    /// @inheritdoc IGatedPoolFactory
    /// @dev Governance-only. The replacement must be an active `FEE_RECIPIENT`
    /// in the venue registry (which also guarantees contract code).
    function setTreasury(address newTreasury) external override onlyGovernance {
        if (newTreasury == address(0)) revert ZeroTreasury();
        if (!IVenueRegistry(venueRegistry).isFacilityOfCategory(newTreasury, FacilityCategory.FEE_RECIPIENT)) {
            revert NotActiveFeeRecipient(newTreasury);
        }

        treasury = newTreasury;
        emit TreasurySet(newTreasury);
    }

    /// @inheritdoc IGatedPoolFactory
    /// @dev Governance-only. The canonical factory must still be owned by this
    /// wrapper; the canonical factory enforces fee/tick-spacing bounds.
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external override onlyGovernance {
        _requireCanonicalOwner();

        IV3FactoryLike(canonicalFactory).enableFeeAmount(fee, tickSpacing);
        emit FeeAmountEnabled(fee, tickSpacing);
    }

    /// @inheritdoc IGatedPoolFactory
    /// @dev Governance-only. Hands canonical factory ownership to `newOwner`;
    /// afterwards `createPool` reverts until ownership is transferred back.
    function transferCanonicalFactoryOwnership(address newOwner) external override onlyGovernance {
        if (newOwner == address(0)) revert ZeroNewOwner();
        _requireCanonicalOwner();

        IV3FactoryLike(canonicalFactory).setOwner(newOwner);
        emit CanonicalFactoryOwnerChanged(newOwner);
    }

    /// @inheritdoc IGatedPoolFactory
    /// @dev A fee is allowed when the canonical factory has a non-zero tick
    /// spacing for it (the four deployment tiers: 100/500/3000/10000).
    function isAllowedFee(uint24 fee) public view override returns (bool) {
        return IV3FactoryLike(canonicalFactory).feeAmountTickSpacing(fee) != 0;
    }

    /// @dev The wrapper must own the canonical factory for pool protocol-fee
    /// operations and fee-tier management to succeed.
    function _requireCanonicalOwner() private view {
        address actualOwner = IV3FactoryLike(canonicalFactory).owner();
        if (actualOwner != address(this)) revert NotCanonicalFactoryOwner(actualOwner, address(this));
    }

    /// @dev `>0` and `<2^160` are implied by the V3 `TickMath` bounds: the
    /// lower bound is inclusive and the upper bound is exclusive.
    function _validateSqrtPrice(uint160 sqrtPriceX96) private pure {
        if (sqrtPriceX96 < MIN_SQRT_RATIO || sqrtPriceX96 >= MAX_SQRT_RATIO) revert InvalidSqrtPrice(sqrtPriceX96);
    }

    /// @dev V3 `setFeeProtocol` bound: disabled or `[4,10]` per side.
    function _validateFeeProtocol(uint8 feeProtocol) private pure {
        if (feeProtocol != 0 && (feeProtocol < 4 || feeProtocol > 10)) revert InvalidProtocolFee(feeProtocol);
    }
}
