// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {LENDING} from "../common/Types.sol";
import {ILendingFacility, IPurposeFacility} from "../interfaces/IPurposeFacility.sol";
import {AgenticFacilityBase} from "./AgenticFacilityBase.sol";

/// @notice PURPOSE/LENDING: the current deployment test-path lending template.
/// @dev No interest, price, oracle or collateral logic: this is an extensibility
/// path, not a production lending product. The owner sets keeper/oracle; lender
/// and borrower are fixed at creation or by the first deposit/borrow. Gated
/// inflows/outflows are agent-only (or the migration target). There is no
/// project withdrawal and no public release/refund/consume.
contract AgenticLendingFacility is AgenticFacilityBase, ILendingFacility {
    using SafeERC20 for IERC20;

    /// @inheritdoc ILendingFacility
    address public override keeper;

    /// @inheritdoc ILendingFacility
    address public override oracle;

    /// @notice Lender fixed at creation or by the first deposit.
    address public lender;

    /// @notice Borrower fixed at creation or by the first borrow.
    address public borrower;

    /// @notice Total lender principal recorded for `token`.
    mapping(address => uint256) public totalDeposited;

    /// @notice Total outstanding test-path debt recorded for `token`.
    mapping(address => uint256) public totalBorrowed;

    error ZeroKeeper();
    error ZeroOracle();
    error ZeroAmount();
    error NotLender(address caller);
    error NotBorrower(address caller);
    error NotKeeperOrOracle(address caller);
    error InsufficientLiquidity(address token, uint256 requested, uint256 available);
    error InsufficientWithdrawal(address token, uint256 requested, uint256 available);
    error RepayExceedsDebt(address token, uint256 requested, uint256 outstanding);
    error ConsumeNotSupported();
    error ReleaseNotSupported();
    error RefundNotSupported();

    /// @notice Emitted when the lender funds the facility.
    event Deposited(address indexed token, address indexed lender, uint256 amount);
    /// @notice Emitted when the borrower draws liquidity.
    event Borrowed(address indexed token, address indexed borrower, uint256 amount);
    /// @notice Emitted when the borrower repays.
    event Repaid(address indexed token, address indexed borrower, uint256 amount);
    /// @notice Emitted when the lender withdraws.
    event Withdrawn(address indexed token, address indexed lender, address indexed to, uint256 amount);
    /// @notice Emitted when keeper/oracle liquidates held liquidity to an agent.
    event Liquidated(address indexed token, address indexed to, uint256 amount);

    /// @param factory_ The facility factory stamp; the factory's deployment helper enforces the caller.
    /// @param venueRegistry_ Venue registry for migration validation.
    /// @param assetRegistry_ Asset registry used to classify gated vs public ERC20.
    /// @param owner_ Project owner (no Agent ID required).
    /// @param keeper_ Liquidation keeper (may be zero; owner sets later).
    /// @param oracle_ Liquidation oracle (may be zero; owner sets later).
    /// @param lender_ Agent lender (may be zero; fixed by the first deposit).
    /// @param borrower_ Agent borrower (may be zero; fixed by the first borrow).
    constructor(
        address factory_,
        address venueRegistry_,
        address assetRegistry_,
        address owner_,
        // Optional roles may be zero and set later/first-deposit/first-borrow.
        // forge-lint: disable-next-line(missing-zero-check)
        address keeper_,
        // forge-lint: disable-next-line(missing-zero-check)
        address oracle_,
        // forge-lint: disable-next-line(missing-zero-check)
        address lender_,
        // forge-lint: disable-next-line(missing-zero-check)
        address borrower_
    ) AgenticFacilityBase(factory_, LENDING, venueRegistry_, assetRegistry_, owner_) {
        keeper = keeper_;
        oracle = oracle_;
        lender = lender_;
        borrower = borrower_;
    }

    /// @inheritdoc ILendingFacility
    function setKeeper(address keeper_) external override onlyOwner {
        if (keeper_ == address(0)) revert ZeroKeeper();
        keeper = keeper_;
        emit KeeperSet(keeper_);
    }

    /// @inheritdoc ILendingFacility
    function setOracle(address oracle_) external override onlyOwner {
        if (oracle_ == address(0)) revert ZeroOracle();
        oracle = oracle_;
        emit OracleSet(oracle_);
    }

    /// @inheritdoc ILendingFacility
    /// @dev Lender-only gated inflow. The lender is fixed at creation or by the
    /// first deposit.
    function deposit(address token, uint256 amount) external override nonReentrant {
        _checkLender(msg.sender);
        _checkGatedToken(token);
        if (amount == 0) revert ZeroAmount();

        totalDeposited[token] += amount;
        emit Deposited(token, msg.sender, amount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc ILendingFacility
    /// @dev Borrower-only gated outflow, limited to recorded lender liquidity.
    function borrow(address token, uint256 amount) external override nonReentrant {
        _checkBorrower(msg.sender);
        _checkGatedRecipient(token, msg.sender);
        if (amount == 0) revert ZeroAmount();

        uint256 available = _available(token);
        if (amount > available) revert InsufficientLiquidity(token, amount, available);
        totalBorrowed[token] += amount;

        emit Borrowed(token, msg.sender, amount);
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /// @inheritdoc ILendingFacility
    /// @dev Borrower-only gated inflow; reduces recorded debt.
    function repay(address token, uint256 amount) external override nonReentrant {
        if (msg.sender != borrower) revert NotBorrower(msg.sender);
        _checkGatedToken(token);
        if (amount == 0) revert ZeroAmount();

        uint256 outstanding = totalBorrowed[token];
        if (amount > outstanding) revert RepayExceedsDebt(token, amount, outstanding);
        totalBorrowed[token] = outstanding - amount;

        emit Repaid(token, msg.sender, amount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc ILendingFacility
    /// @dev Lender-only gated outflow to an agent (or migration target).
    function withdraw(address token, address to, uint256 amount) external override nonReentrant {
        if (msg.sender != lender) revert NotLender(msg.sender);
        _checkGatedRecipient(token, to);
        if (amount == 0) revert ZeroAmount();

        uint256 available = _available(token);
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (amount > available) revert InsufficientWithdrawal(token, amount, available);
        if (amount > balance) revert InsufficientWithdrawal(token, amount, balance);

        totalDeposited[token] -= amount;
        emit Withdrawn(token, msg.sender, to, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IPurposeFacility
    /// @dev Keeper/oracle test path. No price/oracle logic and no collateral:
    /// this transfers held gated liquidity to an agent (or migration target),
    /// reducing recorded lender principal. Production lending is a later
    /// decision; the role-gated path exists to prove extensibility.
    function liquidate(address token, address to, uint256 amount) external override nonReentrant {
        if (msg.sender != keeper && msg.sender != oracle) revert NotKeeperOrOracle(msg.sender);
        _checkGatedRecipient(token, to);
        if (amount == 0) revert ZeroAmount();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (amount > balance) revert InsufficientLiquidity(token, amount, balance);

        uint256 deposited = totalDeposited[token];
        totalDeposited[token] = amount >= deposited ? 0 : deposited - amount;

        emit Liquidated(token, to, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IPurposeFacility
    /// @dev Not part of the LENDING surface; always reverts.
    function consume(address, uint256) external pure override {
        revert ConsumeNotSupported();
    }

    /// @inheritdoc IPurposeFacility
    /// @dev Not part of the LENDING surface; always reverts.
    function release(address, address, uint256) external pure override {
        revert ReleaseNotSupported();
    }

    /// @inheritdoc IPurposeFacility
    /// @dev Not part of the LENDING surface; always reverts.
    function refund(address, address, uint256) external pure override {
        revert RefundNotSupported();
    }

    /// @notice Recorded lender liquidity available to borrow/withdraw.
    function availableOf(address token) external view returns (uint256) {
        return _available(token);
    }

    function _available(address token) private view returns (uint256) {
        uint256 deposited = totalDeposited[token];
        uint256 borrowed = totalBorrowed[token];
        return deposited > borrowed ? deposited - borrowed : 0;
    }

    /// @dev Fixed lender or first-deposit assignment; the caller must be an agent.
    function _checkLender(address caller) private {
        address fixedLender = lender;
        if (fixedLender == address(0)) {
            _requireAgent(caller);
            lender = caller;
            return;
        }
        if (caller != fixedLender) revert NotLender(caller);
    }

    /// @dev Fixed borrower or first-borrow assignment; the caller must be an agent.
    function _checkBorrower(address caller) private {
        address fixedBorrower = borrower;
        if (fixedBorrower == address(0)) {
            _requireAgent(caller);
            borrower = caller;
            return;
        }
        if (caller != fixedBorrower) revert NotBorrower(caller);
    }
}
