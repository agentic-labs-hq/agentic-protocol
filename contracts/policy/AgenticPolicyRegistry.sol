// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "../interfaces/IPolicyRegistry.sol";
import {Governance2Step} from "../common/Governance2Step.sol";

/// @notice Versioned immutable policy registry.
/// @dev A policy is an immutable contract (an `ITransferPolicy` version).
/// Governance can add versions and deprecate them, but can never mutate a
/// policy or redirect an existing token: tokens hold the policy address chosen
/// when they were created.
///
/// `isPolicyAllowed` means "registered and not deprecated". Deprecation clears
/// the flag so new tokens cannot select the policy, while existing tokens keep
/// calling it because they store the address directly.
contract AgenticPolicyRegistry is IPolicyRegistry, Governance2Step {
    /// @inheritdoc IPolicyRegistry
    uint256 public immutable override maxPolicies;

    /// @inheritdoc IPolicyRegistry
    address public override currentPolicy;

    /// @inheritdoc IPolicyRegistry
    mapping(address => uint256) public override policyVersion;

    /// @inheritdoc IPolicyRegistry
    mapping(address => bool) public override isPolicyAllowed;

    address[] private _policies;
    mapping(uint256 => bool) private _versionUsed;

    error InvalidMaxPolicies();
    error ZeroPolicy();
    error PolicyHasNoCode(address policy);
    error PolicyAlreadyAdded(address policy);
    error InvalidVersion();
    error VersionAlreadyUsed(uint256 version);
    error PolicyCapReached(uint256 maxPolicies);
    error PolicyNotAllowed(address policy);
    error PolicyIsCurrent(address policy);

    constructor(address governance_, uint256 maxPolicies_) Governance2Step(governance_) {
        if (maxPolicies_ == 0) revert InvalidMaxPolicies();
        maxPolicies = maxPolicies_;
    }

    /// @inheritdoc IPolicyRegistry
    function policies() external view override returns (address[] memory) {
        return _policies;
    }

    /// @inheritdoc IPolicyRegistry
    function addPolicy(address policy, uint256 version) external override onlyGovernance {
        if (policy == address(0)) revert ZeroPolicy();
        if (policy.code.length == 0) revert PolicyHasNoCode(policy);
        // A deprecated policy keeps its version, so it can never be re-added.
        if (policyVersion[policy] != 0) revert PolicyAlreadyAdded(policy);
        if (version == 0) revert InvalidVersion();
        if (_versionUsed[version]) revert VersionAlreadyUsed(version);
        if (_policies.length >= maxPolicies) revert PolicyCapReached(maxPolicies);

        policyVersion[policy] = version;
        isPolicyAllowed[policy] = true;
        _versionUsed[version] = true;
        _policies.push(policy);

        emit PolicyAdded(policy, version);
    }

    /// @inheritdoc IPolicyRegistry
    /// @dev The policy must be registered and not deprecated.
    function setCurrentPolicy(address policy) external override onlyGovernance {
        if (policy == address(0)) revert ZeroPolicy();
        if (!isPolicyAllowed[policy]) revert PolicyNotAllowed(policy);
        currentPolicy = policy;
        emit CurrentPolicySet(policy);
    }

    /// @inheritdoc IPolicyRegistry
    /// @dev The current policy cannot be deprecated. Deprecation only removes the
    /// policy from new-token selection; existing tokens keep their address.
    function deprecatePolicy(address policy) external override onlyGovernance {
        if (!isPolicyAllowed[policy]) revert PolicyNotAllowed(policy);
        if (policy == currentPolicy) revert PolicyIsCurrent(policy);

        isPolicyAllowed[policy] = false;
        emit PolicyDeprecated(policy, policyVersion[policy]);
    }
}
