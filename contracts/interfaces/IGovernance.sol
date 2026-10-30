// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Two-step governance interface.
interface IGovernance {
    function governance() external view returns (address);
    function pendingGovernance() external view returns (address);
    function transferGovernance(address newGovernance) external;
    function acceptGovernance() external;

    event GovernanceTransferStarted(address indexed current, address indexed pending);
    event GovernanceTransferred(address indexed previous, address indexed newGovernance);
}
