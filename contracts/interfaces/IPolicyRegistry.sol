// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGovernance} from "./IGovernance.sol";

/// @notice Versioned immutable policy registry.
interface IPolicyRegistry is IGovernance {
    function currentPolicy() external view returns (address);
    function policies() external view returns (address[] memory);
    function maxPolicies() external view returns (uint256);
    function policyVersion(address policy) external view returns (uint256);
    function isPolicyAllowed(address policy) external view returns (bool);

    function addPolicy(address policy, uint256 version) external;
    function setCurrentPolicy(address policy) external;
    function deprecatePolicy(address policy) external;

    event PolicyAdded(address indexed policy, uint256 indexed version);
    event CurrentPolicySet(address indexed policy);
    event PolicyDeprecated(address indexed policy, uint256 indexed version);
}
