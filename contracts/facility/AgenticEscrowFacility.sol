// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ESCROW} from "../common/Types.sol";
import {IEscrowFacility, IPurposeFacility} from "../interfaces/IPurposeFacility.sol";
import {AgenticFacilityBase} from "./AgenticFacilityBase.sol";

/// @notice PURPOSE/ESCROW: agent-to-agent trade escrow.
/// @dev The owner sets an arbiter and an agent-only beneficiary before the first
/// deposit. The depositor (fixed at creation or by the first deposit) funds;
/// only the beneficiary/arbiter may release, and only the depositor/arbiter may
/// refund, always to an agent (or the migration target). State is per token so
/// a multi-token escrow resolves each token independently. No public release/
/// refund, no project withdrawal, no native path.
contract AgenticEscrowFacility is AgenticFacilityBase, IEscrowFacility {
    using SafeERC20 for IERC20;

    /// @notice Per-token escrow state.
    enum EscrowState {
        NONE,
        FUNDED,
        RELEASED,
        REFUNDED
    }

    /// @inheritdoc IEscrowFacility
    address public override arbiter;

    /// @inheritdoc IEscrowFacility
    address public override beneficiary;

    /// @notice Depositor fixed at creation or by the first deposit.
    address public depositor;

    /// @notice Whether any token has been deposited (freezes the beneficiary).
    bool public hasDeposit;

    mapping(address => EscrowState) private _state;

    error ZeroArbiter();
    error ZeroBeneficiary();
    error ZeroAmount();
    error BeneficiaryAfterDeposit();
    error NotDepositor(address caller);
    error NotBeneficiaryOrArbiter(address caller);
    error NotDepositorOrArbiter(address caller);
    error InvalidEscrowState(address token, EscrowState state);
    error ConsumeNotSupported();
    error LiquidateNotSupported();

    /// @notice Emitted when the depositor funds a token.
    event Deposited(address indexed token, address indexed depositor, uint256 amount);
    /// @notice Emitted when the escrow releases to an agent.
    event Released(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted when the escrow refunds to an agent.
    event Refunded(address indexed token, address indexed to, uint256 amount);

    /// @param factory_ The facility factory stamp; the factory's deployment helper enforces the caller.
    /// @param venueRegistry_ Venue registry for migration validation.
    /// @param assetRegistry_ Asset registry used to classify gated vs public ERC20.
    /// @param owner_ Project owner (no Agent ID required).
    /// @param arbiter_ Dispute arbiter (may be zero; owner sets later).
    /// @param beneficiary_ Agent beneficiary (may be zero; owner sets before deposit).
    /// @param depositor_ Agent depositor (may be zero; fixed by the first deposit).
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

    /// @inheritdoc IEscrowFacility
    function setArbiter(address arbiter_) external override onlyOwner {
        if (arbiter_ == address(0)) revert ZeroArbiter();
        arbiter = arbiter_;
        emit ArbiterSet(arbiter_);
    }

    /// @inheritdoc IEscrowFacility
    /// @dev Before the first deposit; agent-only, never a facility.
    function setBeneficiary(address beneficiary_) external override onlyOwner {
        if (hasDeposit) revert BeneficiaryAfterDeposit();
        if (beneficiary_ == address(0)) revert ZeroBeneficiary();
        _requireAgent(beneficiary_);
        beneficiary = beneficiary_;
        emit BeneficiarySet(beneficiary_);
    }

    /// @inheritdoc IEscrowFacility
    /// @dev The depositor is fixed at creation or by the first deposit; later
    /// deposits are only from that depositor. Multiple tokens/deposits are
    /// allowed until a token is resolved.
    function deposit(address token, uint256 amount) external override nonReentrant {
        _checkDepositor(msg.sender);
        _checkGatedToken(token);
        if (amount == 0) revert ZeroAmount();
        EscrowState current = _state[token];
        if (current == EscrowState.RELEASED || current == EscrowState.REFUNDED) {
            revert InvalidEscrowState(token, current);
        }

        _state[token] = EscrowState.FUNDED;
        hasDeposit = true;
        emit Deposited(token, msg.sender, amount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc IPurposeFacility
    /// @dev Beneficiary or arbiter, from FUNDED to RELEASED, to an agent/target.
    function release(address token, address to, uint256 amount) external override nonReentrant {
        if (msg.sender != beneficiary && msg.sender != arbiter) revert NotBeneficiaryOrArbiter(msg.sender);
        _checkGatedRecipient(token, to);
        EscrowState current = _state[token];
        if (current != EscrowState.FUNDED) revert InvalidEscrowState(token, current);

        _state[token] = EscrowState.RELEASED;
        emit Released(token, to, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IPurposeFacility
    /// @dev Depositor or arbiter, from FUNDED to REFUNDED, to an agent/target.
    function refund(address token, address to, uint256 amount) external override nonReentrant {
        if (msg.sender != depositor && msg.sender != arbiter) revert NotDepositorOrArbiter(msg.sender);
        _checkGatedRecipient(token, to);
        EscrowState current = _state[token];
        if (current != EscrowState.FUNDED) revert InvalidEscrowState(token, current);

        _state[token] = EscrowState.REFUNDED;
        emit Refunded(token, to, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IPurposeFacility
    /// @dev Not part of the ESCROW surface; always reverts.
    function consume(address, uint256) external pure override {
        revert ConsumeNotSupported();
    }

    /// @inheritdoc IPurposeFacility
    /// @dev Not part of the ESCROW surface; always reverts.
    function liquidate(address, address, uint256) external pure override {
        revert LiquidateNotSupported();
    }

    /// @notice Current escrow state for `token`.
    function stateOf(address token) external view returns (EscrowState) {
        return _state[token];
    }

    /// @dev Fixed depositor or first-deposit assignment. The first depositor
    /// must be an agent; the token policy also enforces Agent->PURPOSE.
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
