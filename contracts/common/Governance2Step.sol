// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGovernance} from "../interfaces/IGovernance.sol";

/// @notice Shared two-step governance used by the protocol policy and venue registries.
/// @dev the public interface §3. Only `governance` can start a transfer; only the
/// pending address can accept it. There is no proxy, no renounce and no
/// alternative admin path shared by the protocol.
abstract contract Governance2Step is IGovernance {
    address private _governance;
    address private _pendingGovernance;

    error ZeroAddress();
    error NotGovernance(address caller);
    error GovernanceUnchanged(address account);
    error NotPendingGovernance(address caller);

    constructor(address governance_) {
        if (governance_ == address(0)) revert ZeroAddress();
        _governance = governance_;
        emit GovernanceTransferred(address(0), governance_);
    }

    modifier onlyGovernance() {
        _checkGovernance();
        _;
    }

    function governance() public view override returns (address) {
        return _governance;
    }

    function pendingGovernance() public view override returns (address) {
        return _pendingGovernance;
    }

    function transferGovernance(address newGovernance) external override onlyGovernance {
        if (newGovernance == address(0)) revert ZeroAddress();
        if (newGovernance == _governance) revert GovernanceUnchanged(newGovernance);
        // Announced by GovernanceTransferStarted below.
        // forge-lint: disable-next-line(missing-events-access-control)
        _pendingGovernance = newGovernance;
        emit GovernanceTransferStarted(_governance, newGovernance);
    }

    function acceptGovernance() external override {
        if (msg.sender != _pendingGovernance) revert NotPendingGovernance(msg.sender);
        address previous = _governance;
        _governance = msg.sender;
        // Announced by GovernanceTransferred below.
        // forge-lint: disable-next-line(missing-events-access-control)
        _pendingGovernance = address(0);
        emit GovernanceTransferred(previous, msg.sender);
    }

    /// @dev Internal check so a contract can apply governance to only one branch
    /// of a function (e.g. `FEE_RECIPIENT` replacement) without a modifier.
    function _checkGovernance() internal view {
        if (msg.sender != _governance) revert NotGovernance(msg.sender);
    }
}
