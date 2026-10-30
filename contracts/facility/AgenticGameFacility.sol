// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {GAME} from "../common/Types.sol";
import {IGameFacility, IPurposeFacility} from "../interfaces/IPurposeFacility.sol";
import {AgenticFacilityBase} from "./AgenticFacilityBase.sol";

/// @notice PURPOSE/GAME sink.
/// @dev The owner-set operator consumes (locks) tokens without changing supply,
/// or releases/refunds them only to agents. Consumed tokens can never leave;
/// the remaining balance is accounted separately. No public consume/release/
/// refund, no project withdrawal, no native path.
contract AgenticGameFacility is AgenticFacilityBase, IGameFacility {
    using SafeERC20 for IERC20;

    /// @inheritdoc IGameFacility
    address public override operator;

    /// @notice Amount of `token` permanently consumed by the game sink.
    mapping(address => uint256) public consumed;

    error ZeroOperator();
    error NotOperator(address caller);
    error ZeroAmount();
    error InsufficientAvailable(address token, uint256 requested, uint256 available);
    error LiquidateNotSupported();

    /// @notice Emitted when the operator consumes (locks) gated tokens.
    event Consumed(address indexed token, uint256 amount);
    /// @notice Emitted when gated tokens are released as a reward.
    event TokenReleased(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted when gated tokens are refunded.
    event TokenRefunded(address indexed token, address indexed to, uint256 amount);

    /// @param factory_ The facility factory stamp; the factory's deployment helper enforces the caller.
    /// @param venueRegistry_ Venue registry for migration validation.
    /// @param assetRegistry_ Asset registry used to classify gated vs public ERC20.
    /// @param owner_ Project owner (no Agent ID required).
    /// @param operator_ Game operator (may be zero; owner sets later).
    constructor(
        address factory_,
        address venueRegistry_,
        address assetRegistry_,
        address owner_,
        // Optional; the owner may set it later.
        // forge-lint: disable-next-line(missing-zero-check)
        address operator_
    )
        AgenticFacilityBase(factory_, GAME, venueRegistry_, assetRegistry_, owner_)
    {
        operator = operator_;
    }

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator(msg.sender);
        _;
    }

    /// @inheritdoc IGameFacility
    function setOperator(address operator_) external override onlyOwner {
        if (operator_ == address(0)) revert ZeroOperator();
        operator = operator_;
        emit OperatorSet(operator_);
    }

    /// @inheritdoc IPurposeFacility
    /// @dev Locks `amount` of `token` in the sink. No transfer and no supply
    /// change; consumed amounts are permanently unavailable to release/refund.
    function consume(address token, uint256 amount) external override nonReentrant onlyOperator {
        _checkGatedToken(token);
        if (amount == 0) revert ZeroAmount();
        uint256 available = availableOf(token);
        if (amount > available) revert InsufficientAvailable(token, amount, available);
        consumed[token] += amount;
        emit Consumed(token, amount);
    }

    /// @inheritdoc IPurposeFacility
    /// @dev Operator-only reward; recipient must be an agent (or target).
    function release(address token, address to, uint256 amount) external override nonReentrant onlyOperator {
        _checkGatedRecipient(token, to);
        _checkAvailable(token, amount);
        emit TokenReleased(token, to, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IPurposeFacility
    /// @dev Operator-only refund; recipient must be an agent (or target).
    function refund(address token, address to, uint256 amount) external override nonReentrant onlyOperator {
        _checkGatedRecipient(token, to);
        _checkAvailable(token, amount);
        emit TokenRefunded(token, to, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IPurposeFacility
    /// @dev Not part of the GAME surface; always reverts.
    function liquidate(address, address, uint256) external pure override {
        revert LiquidateNotSupported();
    }

    /// @notice Gated balance that is not permanently consumed.
    function availableOf(address token) public view returns (uint256) {
        if (token == address(0)) return 0;
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 locked = consumed[token];
        return balance > locked ? balance - locked : 0;
    }

    function _checkAvailable(address token, uint256 amount) private view {
        uint256 available = availableOf(token);
        if (amount > available) revert InsufficientAvailable(token, amount, available);
    }
}
