// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {FacilityCategory} from "../common/Types.sol";
import {Governance2Step} from "../common/Governance2Step.sol";
import {IAgentToken} from "../interfaces/IAgentAsset.sol";
import {IAssetRegistry} from "../interfaces/IAssetRegistry.sol";
import {IMigratableFacility} from "../interfaces/IFacility.sol";
import {IProtocolTreasury} from "../interfaces/IProtocolTreasury.sol";
import {ITransferPolicy} from "../interfaces/ITransferPolicy.sol";
import {IVenueRegistry} from "../interfaces/IVenueRegistry.sol";

import {ISwapRouter} from "./ISwapRouter.sol";

/// @notice Protocol treasury / `FEE_RECIPIENT`.
/// @dev Governance-owned, no Agent ID, no proxy. Gated fees are a stopover:
/// they leave only to agents, except for the one registry-validated migration
/// path. Public assets are free but the swap path is public-assets-only.
/// There is no arbitrary call, no delegatecall and no router setter.
contract AgenticTreasury is IProtocolTreasury, Governance2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Hard upper bound for the constructor `maxDistributionBatch`.
    /// @dev Bounds the per-call loop; governance still chooses the value.
    uint256 public constant MAX_DISTRIBUTION_BATCH_LIMIT = 256;

    /// @inheritdoc IProtocolTreasury
    address public immutable override assetRegistry;

    /// @inheritdoc IProtocolTreasury
    address public immutable override facilityRegistry;

    /// @inheritdoc IProtocolTreasury
    /// @dev Fixed at construction; there is no setter and no per-call router.
    address public immutable override router;

    /// @inheritdoc IProtocolTreasury
    uint256 public immutable override maxDistributionBatch;

    /// @dev Set by `migrate`; the only non-agent address that may receive gated
    /// tokens from this treasury. The token's own policy still enforces that a
    /// revoked treasury can only send gated to its active registry replacement.
    address private _migrationTarget;

    error NotContract(address account);
    error InvalidDistributionBatch(uint256 value, uint256 max);
    error GatedRecipientNotAgent(address token, address recipient);
    error GatedSwapNotAllowed();
    error ZeroAmount();
    error IdenticalTokens(address token);
    error DeadlineExpired(uint256 deadline);
    error InsufficientOutput(uint256 amountOut, uint256 amountOutMinimum);
    error LengthMismatch(uint256 recipientsLength, uint256 amountsLength);
    error BatchTooLarge(uint256 length, uint256 max);
    error ReplacementIsSelf();
    error TreasuryNotRevoked();
    error NotRegistryReplacement(address expected, address actual);
    error ReplacementNotFeeRecipient(address replacement);

    constructor(
        address assetRegistry_,
        address facilityRegistry_,
        address router_,
        uint256 maxDistributionBatch_,
        address governance_
    ) Governance2Step(governance_) {
        if (assetRegistry_ == address(0) || facilityRegistry_ == address(0) || router_ == address(0)) {
            revert ZeroAddress();
        }
        if (assetRegistry_.code.length == 0) revert NotContract(assetRegistry_);
        if (facilityRegistry_.code.length == 0) revert NotContract(facilityRegistry_);
        if (router_.code.length == 0) revert NotContract(router_);
        if (maxDistributionBatch_ == 0 || maxDistributionBatch_ > MAX_DISTRIBUTION_BATCH_LIMIT) {
            revert InvalidDistributionBatch(maxDistributionBatch_, MAX_DISTRIBUTION_BATCH_LIMIT);
        }

        assetRegistry = assetRegistry_;
        facilityRegistry = facilityRegistry_;
        router = router_;
        maxDistributionBatch = maxDistributionBatch_;
    }

    /// @notice Accepts public native protocol fees.
    receive() external payable override {}

    /// @inheritdoc IProtocolTreasury
    /// @dev Gated tokens leave only to an agent under the token's own policy.
    /// The single exception is the migration target chosen by `migrate`, and
    /// only while this treasury is revoked with the registry still pointing at
    /// that target. The token policy decides whether the replacement may receive.
    function transferToken(address token, address to, uint256 amount) external override nonReentrant onlyGovernance {
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        _checkGatedRecipient(token, to);
        emit TreasuryTransfer(token, to, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IProtocolTreasury
    /// @dev Native is a public asset: governance may send it anywhere.
    function transferNative(address payable to, uint256 amount) external override nonReentrant onlyGovernance {
        if (to == address(0)) revert ZeroAddress();
        emit TreasuryTransfer(address(0), to, amount);
        Address.sendValue(to, amount);
    }

    /// @inheritdoc IProtocolTreasury
    /// @dev Public-assets-only: both legs must be unregistered (non-gated).
    /// The router is immutable, the recipient is this treasury, the approval is
    /// exact and reset, and output/deadline are enforced here as well as by the
    /// router.
    function swapExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) external override nonReentrant onlyGovernance returns (uint256 amountOut) {
        if (tokenIn == address(0) || tokenOut == address(0)) revert ZeroAddress();
        if (tokenIn == tokenOut) revert IdenticalTokens(tokenIn);
        if (amountIn == 0) revert ZeroAmount();
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > deadline) revert DeadlineExpired(deadline);

        IAssetRegistry registry = IAssetRegistry(assetRegistry);
        if (registry.isRegistered(tokenIn) || registry.isRegistered(tokenOut)) revert GatedSwapNotAllowed();

        IERC20(tokenIn).forceApprove(router, amountIn);
        // forge-lint: disable-next-line(reentrancy-no-eth)
        amountOut = ISwapRouter(router)
            .exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: fee,
                    recipient: address(this),
                    deadline: deadline,
                    amountIn: amountIn,
                    amountOutMinimum: amountOutMinimum,
                    sqrtPriceLimitX96: 0
                })
            );
        IERC20(tokenIn).forceApprove(router, 0);

        if (amountOut < amountOutMinimum) revert InsufficientOutput(amountOut, amountOutMinimum);
        // forge-lint: disable-next-line(reentrancy-events)
        emit TreasurySwap(tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @inheritdoc IProtocolTreasury
    /// @dev Gated recipients must be agents; public recipients are free. The
    /// batch is bounded by `maxDistributionBatch`.
    function distributeToken(address token, address[] calldata recipients, uint256[] calldata amounts)
        external
        override
        nonReentrant
        onlyGovernance
    {
        if (token == address(0)) revert ZeroAddress();
        uint256 length = recipients.length;
        if (length != amounts.length) revert LengthMismatch(length, amounts.length);
        if (length > maxDistributionBatch) revert BatchTooLarge(length, maxDistributionBatch);

        bool gated = IAssetRegistry(assetRegistry).isRegistered(token);
        address policy = gated ? IAgentToken(token).policy() : address(0);
        IVenueRegistry venue = IVenueRegistry(facilityRegistry);

        for (uint256 i; i < length; ++i) {
            address recipient = recipients[i];
            // forge-lint: disable-next-line(require-revert-in-loop)
            if (recipient == address(0)) revert ZeroAddress();
            // forge-lint: disable-next-line(calls-loop)
            if (gated && venue.isRevokedFacility(recipient)) {
                // forge-lint: disable-next-line(require-revert-in-loop)
                revert GatedRecipientNotAgent(token, recipient);
            }
            // forge-lint: disable-next-line(calls-loop)
            if (gated && !ITransferPolicy(policy).isMember(recipient)) {
                // forge-lint: disable-next-line(require-revert-in-loop)
                revert GatedRecipientNotAgent(token, recipient);
            }
            // Revoked facilities are frozen even if they also hold an Agent ID.
            if (gated && ITransferPolicy(policy).isRevokedFacility(recipient)) {
                // forge-lint: disable-next-line(require-revert-in-loop)
                revert GatedRecipientNotAgent(token, recipient);
            }
            emit TreasuryTransfer(token, recipient, amounts[i]);
            // forge-lint: disable-next-line(calls-loop)
            IERC20(token).safeTransfer(recipient, amounts[i]);
        }
    }

    /// @inheritdoc IMigratableFacility
    /// @dev Validates the active `FEE_RECIPIENT` replacement and records it as
    /// the only non-agent gated recipient. This treasury must first be revoked
    /// and the registry replacement must be exactly `replacement`. It cannot
    /// atomically sweep arbitrary ERC-20 balances (the frozen signature has no
    /// token list); governance moves each gated balance with `transferToken`
    /// afterwards. Public assets (including native) are never moved by
    /// `migrate`.
    function migrate(address replacement) external override nonReentrant onlyGovernance {
        if (replacement == address(0)) revert ZeroAddress();
        if (replacement == address(this)) revert ReplacementIsSelf();

        IVenueRegistry venue = IVenueRegistry(facilityRegistry);
        if (!venue.isRevokedFacility(address(this))) revert TreasuryNotRevoked();
        address expected = venue.replacementOf(address(this));
        if (expected != replacement) revert NotRegistryReplacement(expected, replacement);
        if (!venue.isFacilityOfCategory(replacement, FacilityCategory.FEE_RECIPIENT)) {
            revert ReplacementNotFeeRecipient(replacement);
        }

        _migrationTarget = replacement;
        emit TreasuryMigrated(replacement);
    }

    /// @dev A gated recipient is either an agent under the token's policy or the
    /// migration target. The migration target is accepted only while this
    /// treasury is revoked and the registry still points at it, so a permissive
    /// token policy cannot turn migration into a general gated bypass. The
    /// token's own policy remains the final authority for the actual transfer.
    function _checkGatedRecipient(address token, address to) private view {
        if (!IAssetRegistry(assetRegistry).isRegistered(token)) return;
        if (_isActiveMigrationTarget(to)) return;
        // Registry-level defence in depth: even a permissive/future token
        // policy cannot make the treasury itself pay a revoked facility.
        if (IVenueRegistry(facilityRegistry).isRevokedFacility(to)) revert GatedRecipientNotAgent(token, to);
        address policy = IAgentToken(token).policy();
        if (ITransferPolicy(policy).isRevokedFacility(to)) revert GatedRecipientNotAgent(token, to);
        if (!ITransferPolicy(policy).isMember(to)) {
            revert GatedRecipientNotAgent(token, to);
        }
    }

    /// @dev The recorded target plus the live venue-registry checks. Mirror
    /// `AgenticFacilityBase`: the target must still be the active FEE replacement and
    /// keep the same subtype, not merely be the recorded address.
    function _isActiveMigrationTarget(address to) private view returns (bool) {
        if (_migrationTarget == address(0) || to != _migrationTarget) return false;
        IVenueRegistry venue = IVenueRegistry(facilityRegistry);
        if (!venue.isRevokedFacility(address(this))) return false;
        if (venue.replacementOf(address(this)) != to) return false;
        if (!venue.isFacilityOfCategory(to, FacilityCategory.FEE_RECIPIENT)) return false;
        if (venue.isRevokedFacility(to)) return false;
        return venue.facilityType(address(this)) == venue.facilityType(to);
    }
}
