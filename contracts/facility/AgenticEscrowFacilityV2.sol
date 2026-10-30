// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ESCROW} from "../common/Types.sol";
import {IEscrowFacility, IPurposeFacility} from "../interfaces/IPurposeFacility.sol";
import {AgenticFacilityBase} from "./AgenticFacilityBase.sol";

/// @notice PURPOSE/ESCROW v2: role-controlled, partial-settlement escrow.
/// @dev v2 removes the per-token one-shot state machine. Any gated balance can
/// be released/refunded in one or more calls, with amount > 0 and amount <=
/// current balance. This covers direct mint/transfer and migration receipt
/// without requiring a `deposit` call, and prevents the v1 terminal-state lock.
///
/// Roles are unchanged: beneficiary/arbiter release; depositor/arbiter refund;
/// every recipient is an agent or the active migration target. The V2 factory
/// requires a non-zero beneficiary and depositor for an ESCROW instance; the
/// zero-role canonical template deployment is used only for codehash and is
/// never registered. `deposit` freezes the beneficiary after normal funding.
contract AgenticEscrowFacilityV2 is AgenticFacilityBase, IEscrowFacility {
    using SafeERC20 for IERC20;

    /// @notice Once a token settlement starts, it stays in that mode. Partial
    /// amounts are still allowed; this only prevents release/refund flip-flop.
    enum SettlementMode {
        NONE,
        RELEASE,
        REFUND
    }

    /// @notice Roles.
    address public override arbiter;
    address public override beneficiary;
    address public depositor;

    /// @notice Whether a `deposit` or a settlement has occurred; freezes the
    /// beneficiary only for the normal deposit/settlement path. Direct mint or
    /// transfer is intentionally not a deposit and does not set it.
    bool public hasDeposit;

    mapping(address => SettlementMode) private _mode;
    mapping(address => bool) private _settled;

    error ZeroArbiter();
    error ZeroBeneficiary();
    error ZeroAmount();
    error BeneficiaryAfterDeposit();
    error NotDepositor(address caller);
    error NotBeneficiaryOrArbiter(address caller);
    error NotDepositorOrArbiter(address caller);
    error InsufficientBalance(address token, uint256 requested, uint256 available);
    error SettlementModeLocked(address token, SettlementMode mode);
    error EscrowAlreadySettled(address token);
    error ConsumeNotSupported();
    error LiquidateNotSupported();

    event Deposited(address indexed token, address indexed depositor, uint256 amount);
    event Released(address indexed token, address indexed to, uint256 amount);
    event Refunded(address indexed token, address indexed to, uint256 amount);

    constructor(
        address factory_,
        address venueRegistry_,
        address assetRegistry_,
        address owner_,
        // Optional roles may be zero and set later/first-deposit.
        // forge-lint: disable-next-line(missing-zero-check)
        address arbiter_,
        // forge-lint: disable-next-line(missing-zero-check)
        address beneficiary_,
        // forge-lint: disable-next-line(missing-zero-check)
        address depositor_
    ) AgenticFacilityBase(factory_, ESCROW, venueRegistry_, assetRegistry_, owner_) {
        arbiter = arbiter_;
        beneficiary = beneficiary_;
        depositor = depositor_;
    }

    function setArbiter(address arbiter_) external override onlyOwner {
        if (arbiter_ == address(0)) revert ZeroArbiter();
        arbiter = arbiter_;
        emit ArbiterSet(arbiter_);
    }

    function setBeneficiary(address beneficiary_) external override onlyOwner {
        if (hasDeposit) revert BeneficiaryAfterDeposit();
        if (beneficiary_ == address(0)) revert ZeroBeneficiary();
        _requireAgent(beneficiary_);
        beneficiary = beneficiary_;
        emit BeneficiarySet(beneficiary_);
    }

    /// @dev Gated deposit; fixes the depositor on the first call. Multiple
    /// deposits are allowed. No terminal state is stored.
    function deposit(address token, uint256 amount) external override nonReentrant {
        _checkDepositor(msg.sender);
        _checkGatedToken(token);
        if (amount == 0) revert ZeroAmount();
        if (_settled[token]) revert EscrowAlreadySettled(token);

        hasDeposit = true;
        emit Deposited(token, msg.sender, amount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @dev Beneficiary/arbiter release. Partial amounts are allowed; the
    /// remaining balance stays releasable in RELEASE mode. `hasDeposit` freezes
    /// the beneficiary after the first settlement.
    function release(address token, address to, uint256 amount) external override nonReentrant {
        if (msg.sender != beneficiary && msg.sender != arbiter) revert NotBeneficiaryOrArbiter(msg.sender);
        _checkGatedRecipient(token, to);
        uint256 available = _checkAmount(token, amount);
        SettlementMode mode = _mode[token];
        if (mode == SettlementMode.REFUND) revert SettlementModeLocked(token, mode);
        _mode[token] = SettlementMode.RELEASE;
        if (amount == available) _settled[token] = true;

        hasDeposit = true;
        emit Released(token, to, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @dev Depositor/arbiter refund. Partial amounts are allowed in REFUND
    /// mode. The V2 factory requires a non-zero depositor; the template's
    /// canonical zero-role deployment is not registered.
    function refund(address token, address to, uint256 amount) external override nonReentrant {
        if (msg.sender != depositor && msg.sender != arbiter) revert NotDepositorOrArbiter(msg.sender);
        _checkGatedRecipient(token, to);
        uint256 available = _checkAmount(token, amount);
        SettlementMode mode = _mode[token];
        if (mode == SettlementMode.RELEASE) revert SettlementModeLocked(token, mode);
        _mode[token] = SettlementMode.REFUND;
        if (amount == available) _settled[token] = true;

        hasDeposit = true;
        emit Refunded(token, to, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    function consume(address, uint256) external pure override {
        revert ConsumeNotSupported();
    }

    function liquidate(address, address, uint256) external pure override {
        revert LiquidateNotSupported();
    }

    function _checkAmount(address token, uint256 amount) private view returns (uint256 available) {
        if (amount == 0) revert ZeroAmount();
        available = IERC20(token).balanceOf(address(this));
        if (amount > available) revert InsufficientBalance(token, amount, available);
    }

    function _checkDepositor(address caller) private {
        address fixedDepositor = depositor;
        if (fixedDepositor == address(0)) {
            _requireAgent(caller);
            depositor = caller;
            return;
        }
        if (caller != fixedDepositor) revert NotDepositor(caller);
    }
}
