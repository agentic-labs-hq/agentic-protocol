// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {Governance2Step} from "../../contracts/common/Governance2Step.sol";
import {AgenticPolicyRegistry} from "../../contracts/policy/AgenticPolicyRegistry.sol";
import {MockPolicy} from "../mocks/MockPolicy.sol";

contract AgenticPolicyRegistryTest is Test {
    event PolicyAdded(address indexed policy, uint256 indexed version);
    event CurrentPolicySet(address indexed policy);
    event PolicyDeprecated(address indexed policy, uint256 indexed version);
    event GovernanceTransferStarted(address indexed current, address indexed pending);
    event GovernanceTransferred(address indexed previous, address indexed newGovernance);

    AgenticPolicyRegistry internal registry;
    MockPolicy internal p1;
    MockPolicy internal p2;
    MockPolicy internal p3;
    MockPolicy internal p4;

    address internal nonGov = address(0xBAD);

    function setUp() public {
        registry = new AgenticPolicyRegistry(address(this), 3);
        p1 = new MockPolicy(1);
        p2 = new MockPolicy(2);
        p3 = new MockPolicy(3);
        p4 = new MockPolicy(4);
    }

    function testInitialState() public view {
        assertEq(registry.governance(), address(this));
        assertEq(registry.pendingGovernance(), address(0));
        assertEq(registry.maxPolicies(), 3);
        assertEq(registry.currentPolicy(), address(0));
        assertEq(registry.policies().length, 0);
        assertFalse(registry.isPolicyAllowed(address(p1)));
    }

    function testConstructorRejectsZeroGovernance() public {
        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        new AgenticPolicyRegistry(address(0), 1);
    }

    function testConstructorRejectsZeroCap() public {
        vm.expectRevert(AgenticPolicyRegistry.InvalidMaxPolicies.selector);
        new AgenticPolicyRegistry(address(this), 0);
    }

    function testAddPolicy() public {
        vm.expectEmit(true, true, false, true, address(registry));
        emit PolicyAdded(address(p1), 1);
        registry.addPolicy(address(p1), 1);

        assertEq(registry.policyVersion(address(p1)), 1);
        assertTrue(registry.isPolicyAllowed(address(p1)));
        address[] memory listed = registry.policies();
        assertEq(listed.length, 1);
        assertEq(listed[0], address(p1));
    }

    function testAddPolicyOnlyGovernance() public {
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonGov));
        registry.addPolicy(address(p1), 1);
    }

    function testAddPolicyZeroAddress() public {
        vm.expectRevert(AgenticPolicyRegistry.ZeroPolicy.selector);
        registry.addPolicy(address(0), 1);
    }

    function testAddPolicyWithoutCode() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticPolicyRegistry.PolicyHasNoCode.selector, nonGov));
        registry.addPolicy(nonGov, 1);
    }

    function testAddPolicyZeroVersion() public {
        vm.expectRevert(AgenticPolicyRegistry.InvalidVersion.selector);
        registry.addPolicy(address(p1), 0);
    }

    function testAddPolicyUniquePolicy() public {
        registry.addPolicy(address(p1), 1);
        vm.expectRevert(abi.encodeWithSelector(AgenticPolicyRegistry.PolicyAlreadyAdded.selector, address(p1)));
        registry.addPolicy(address(p1), 2);
    }

    function testAddPolicyUniqueVersion() public {
        registry.addPolicy(address(p1), 1);
        vm.expectRevert(abi.encodeWithSelector(AgenticPolicyRegistry.VersionAlreadyUsed.selector, 1));
        registry.addPolicy(address(p2), 1);
    }

    function testAddPolicyCap() public {
        registry.addPolicy(address(p1), 1);
        registry.addPolicy(address(p2), 2);
        registry.addPolicy(address(p3), 3);
        vm.expectRevert(abi.encodeWithSelector(AgenticPolicyRegistry.PolicyCapReached.selector, 3));
        registry.addPolicy(address(p4), 4);
    }

    function testCapIsConstructorBound() public {
        AgenticPolicyRegistry capped = new AgenticPolicyRegistry(address(this), 1);
        capped.addPolicy(address(p1), 1);
        vm.expectRevert(abi.encodeWithSelector(AgenticPolicyRegistry.PolicyCapReached.selector, 1));
        capped.addPolicy(address(p2), 2);
    }

    function testSetCurrentPolicy() public {
        registry.addPolicy(address(p1), 1);
        registry.addPolicy(address(p2), 2);

        vm.expectEmit(true, false, false, true, address(registry));
        emit CurrentPolicySet(address(p1));
        registry.setCurrentPolicy(address(p1));
        assertEq(registry.currentPolicy(), address(p1));

        vm.expectEmit(true, false, false, true, address(registry));
        emit CurrentPolicySet(address(p2));
        registry.setCurrentPolicy(address(p2));
        assertEq(registry.currentPolicy(), address(p2));
    }

    function testSetCurrentPolicyOnlyGovernance() public {
        registry.addPolicy(address(p1), 1);
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonGov));
        registry.setCurrentPolicy(address(p1));
    }

    function testSetCurrentPolicyZero() public {
        vm.expectRevert(AgenticPolicyRegistry.ZeroPolicy.selector);
        registry.setCurrentPolicy(address(0));
    }

    function testSetCurrentPolicyUnregistered() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticPolicyRegistry.PolicyNotAllowed.selector, address(p1)));
        registry.setCurrentPolicy(address(p1));
    }

    function testSetSameCurrentPolicyIsIdempotent() public {
        registry.addPolicy(address(p1), 1);
        registry.setCurrentPolicy(address(p1));
        registry.setCurrentPolicy(address(p1));
        assertEq(registry.currentPolicy(), address(p1));
    }

    function testDeprecatePolicy() public {
        registry.addPolicy(address(p1), 1);
        registry.addPolicy(address(p2), 2);
        registry.setCurrentPolicy(address(p2));

        vm.expectEmit(true, true, false, true, address(registry));
        emit PolicyDeprecated(address(p1), 1);
        registry.deprecatePolicy(address(p1));

        assertFalse(registry.isPolicyAllowed(address(p1)));
        assertEq(registry.policyVersion(address(p1)), 1);
        // Existing tokens keep the policy: registration/version data is retained.
        address[] memory listed = registry.policies();
        assertEq(listed.length, 2);
        assertEq(listed[0], address(p1));
    }

    function testDeprecatedPolicyCannotBeSelected() public {
        registry.addPolicy(address(p1), 1);
        registry.addPolicy(address(p2), 2);
        registry.setCurrentPolicy(address(p2));
        registry.deprecatePolicy(address(p1));

        vm.expectRevert(abi.encodeWithSelector(AgenticPolicyRegistry.PolicyNotAllowed.selector, address(p1)));
        registry.setCurrentPolicy(address(p1));
    }

    function testDeprecatedPolicyCannotBeReAdded() public {
        registry.addPolicy(address(p1), 1);
        registry.addPolicy(address(p2), 2);
        registry.setCurrentPolicy(address(p2));
        registry.deprecatePolicy(address(p1));

        vm.expectRevert(abi.encodeWithSelector(AgenticPolicyRegistry.PolicyAlreadyAdded.selector, address(p1)));
        registry.addPolicy(address(p1), 9);
    }

    function testDeprecateTwiceReverts() public {
        registry.addPolicy(address(p1), 1);
        registry.addPolicy(address(p2), 2);
        registry.setCurrentPolicy(address(p2));
        registry.deprecatePolicy(address(p1));

        vm.expectRevert(abi.encodeWithSelector(AgenticPolicyRegistry.PolicyNotAllowed.selector, address(p1)));
        registry.deprecatePolicy(address(p1));
    }

    function testCannotDeprecateCurrentPolicy() public {
        registry.addPolicy(address(p1), 1);
        registry.setCurrentPolicy(address(p1));

        vm.expectRevert(abi.encodeWithSelector(AgenticPolicyRegistry.PolicyIsCurrent.selector, address(p1)));
        registry.deprecatePolicy(address(p1));
    }

    function testDeprecateUnregisteredPolicy() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticPolicyRegistry.PolicyNotAllowed.selector, address(p1)));
        registry.deprecatePolicy(address(p1));
    }

    function testDeprecateOnlyGovernance() public {
        registry.addPolicy(address(p1), 1);
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonGov));
        registry.deprecatePolicy(address(p1));
    }

    function testTransferGovernanceTwoStep() public {
        address newGov = address(0xC0FFEE);

        vm.expectEmit(true, true, false, true, address(registry));
        emit GovernanceTransferStarted(address(this), newGov);
        registry.transferGovernance(newGov);
        assertEq(registry.pendingGovernance(), newGov);
        assertEq(registry.governance(), address(this));

        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotPendingGovernance.selector, nonGov));
        registry.acceptGovernance();

        vm.expectEmit(true, true, false, true, address(registry));
        emit GovernanceTransferred(address(this), newGov);
        vm.prank(newGov);
        registry.acceptGovernance();
        assertEq(registry.governance(), newGov);
        assertEq(registry.pendingGovernance(), address(0));
    }

    function testOldGovernanceLosesAccessAfterTransfer() public {
        address newGov = address(0xC0FFEE);
        registry.transferGovernance(newGov);
        vm.prank(newGov);
        registry.acceptGovernance();

        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, address(this)));
        registry.addPolicy(address(p1), 1);

        vm.prank(newGov);
        registry.addPolicy(address(p1), 1);
        assertTrue(registry.isPolicyAllowed(address(p1)));
    }

    function testTransferGovernanceZero() public {
        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        registry.transferGovernance(address(0));
    }

    function testTransferGovernanceToSelf() public {
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.GovernanceUnchanged.selector, address(this)));
        registry.transferGovernance(address(this));
    }

    function testTransferGovernanceOnlyGovernance() public {
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonGov));
        registry.transferGovernance(nonGov);
    }

    function testTransferGovernanceOverwritesPending() public {
        address first = address(0xC0FFEE);
        address second = address(0xF00D);
        registry.transferGovernance(first);
        registry.transferGovernance(second);
        assertEq(registry.pendingGovernance(), second);

        vm.prank(first);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotPendingGovernance.selector, first));
        registry.acceptGovernance();

        vm.prank(second);
        registry.acceptGovernance();
        assertEq(registry.governance(), second);
    }
}
