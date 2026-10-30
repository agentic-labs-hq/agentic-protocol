// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {LAUNCH} from "../common/Types.sol";
import {ICustodyFacility, ILaunchFacility} from "../interfaces/ICustodyFacility.sol";
import {AgenticFacilityBase} from "./AgenticFacilityBase.sol";

/// @notice CUSTODY/LAUNCH: primary sale custody.
/// @dev Owner sets the project operator and the agent-only beneficiary. The
/// operator releases gated tokens to agent buyers; after `close` the remaining
/// gated balance may only go to the beneficiary (or the migration target).
/// Payments are external to this template. `close` cannot enumerate tokens, so
/// it marks the sale closed; the operator then uses `release` for each unsold
/// token. There is no public release and no facility recipient (outside the
/// active migration target).
contract AgenticLaunchFacility is AgenticFacilityBase, ILaunchFacility {
    using SafeERC20 for IERC20;

    /// @inheritdoc ILaunchFacility
    address public override operator;

    /// @inheritdoc ILaunchFacility
    address public override beneficiary;

    /// @notice Whether the primary sale has been closed by owner/operator.
    bool public closed;

    error ZeroOperator();
    error ZeroBeneficiary();
    error AlreadyClosed();
    error NotOperator(address caller);
    error NotOwnerOrOperator(address caller);
    error ClosedRecipientNotBeneficiary(address recipient);
    error BeneficiaryNotSet();

    /// @notice Emitted when gated or public tokens are released.
    event TokenReleased(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted when public native is released.
    event NativeReleased(address indexed to, uint256 amount);

    /// @param factory_ The facility factory stamp; the factory's deployment helper enforces the caller.
    /// @param venueRegistry_ Venue registry for migration validation.
    /// @param assetRegistry_ Asset registry used to classify gated vs public ERC20.
    /// @param owner_ Project owner (no Agent ID required).
    /// @param operator_ Project sale operator (may be zero; owner sets later).
    /// @param beneficiary_ Agent beneficiary for unsold tokens (may be zero).
    constructor(
        address factory_,
        address venueRegistry_,
        address assetRegistry_,
        address owner_,
        // Optional roles may be zero and set later by the owner.
        // forge-lint: disable-next-line(missing-zero-check)
        address operator_,
        // forge-lint: disable-next-line(missing-zero-check)
        address beneficiary_
    ) AgenticFacilityBase(factory_, LAUNCH, venueRegistry_, assetRegistry_, owner_) {
        operator = operator_;
        beneficiary = beneficiary_;
    }

    /// @notice Accept public native.
    receive() external payable {}

    modifier onlyOwnerOrOperator() {
        if (msg.sender != owner && msg.sender != operator) revert NotOwnerOrOperator(msg.sender);
        _;
    }

    /// @inheritdoc ILaunchFacility
    function setOperator(address operator_) external override onlyOwner {
        if (operator_ == address(0)) revert ZeroOperator();
        operator = operator_;
        emit OperatorSet(operator_);
    }

    /// @inheritdoc ILaunchFacility
    /// @dev Agent-only, never a facility.
    function setBeneficiary(address beneficiary_) external override onlyOwner {
        if (beneficiary_ == address(0)) revert ZeroBeneficiary();
        _requireAgent(beneficiary_);
        beneficiary = beneficiary_;
        emit BeneficiarySet(beneficiary_);
    }

    /// @inheritdoc ICustodyFacility
    /// @dev Gated tokens: operator-only primary sale, to an agent (or active
    /// migration target); after close, unsold gated may only go to the agent
    /// beneficiary (or migration target). Public ERC20: owner-only, any
    /// non-zero recipient; public assets are free.
    function release(address token, address to, uint256 amount) external override nonReentrant {
        if (token == address(0)) revert ZeroToken();
        if (to == address(0)) revert ZeroRecipient();

        if (_isGated(token)) {
            if (msg.sender != operator) revert NotOperator(msg.sender);
            if (closed && to != beneficiary && !_isActiveMigrationTarget(to)) {
                revert ClosedRecipientNotBeneficiary(to);
            }
            _checkGatedRecipient(token, to);
        } else if (msg.sender != owner) {
            revert NotOwner(msg.sender);
        }

        emit TokenReleased(token, to, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc ILaunchFacility
    /// @dev Owner or operator closes the primary sale. The beneficiary must be
    /// set to an agent so unsold gated tokens have a valid recipient.
    function close() external override onlyOwnerOrOperator {
        if (closed) revert AlreadyClosed();
        if (beneficiary == address(0)) revert BeneficiaryNotSet();
        _requireAgent(beneficiary);
        closed = true;
        emit Closed();
    }

    /// @inheritdoc ICustodyFacility
    /// @dev Owner-only public native; no agent restriction.
    function releaseNative(address payable to, uint256 amount) external override nonReentrant onlyOwner {
        emit NativeReleased(to, amount);
        _sendNative(to, amount);
    }
}
