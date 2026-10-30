// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgenticFacilityBase} from "../../contracts/facility/AgenticFacilityBase.sol";
import {AgenticLaunchFacility} from "../../contracts/facility/AgenticLaunchFacility.sol";
import {AgenticVaultFacility} from "../../contracts/facility/AgenticVaultFacility.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";

import {MockToken} from "../mocks/MockToken.sol";
import {FacilityFixture} from "../helpers/FacilityFixture.sol";

contract AgenticLaunchFacilityTest is FacilityFixture {
    AgenticLaunchFacility internal launch;
    AgenticToken internal token;

    function setUp() public {
        _deployFacilities();
        launch = _defaultLaunch();
        token = _fundLaunch(launch, 1_000 ether);
    }

    function testLaunchReleaseOperatorToAgentBuyer() public {
        vm.prank(projectOwner);
        launch.release(address(token), agent2, 250 ether);

        assertEq(token.balanceOf(agent2), 250 ether);
        assertEq(token.balanceOf(address(launch)), 750 ether);
    }

    function testLaunchReleaseOnlyOperator() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticLaunchFacility.NotOperator.selector, agent));
        launch.release(address(token), agent2, 1 ether);

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticLaunchFacility.NotOperator.selector, nonAgent));
        launch.release(address(token), agent2, 1 ether);
    }

    function testLaunchPublicERC20OwnerOnly() public {
        AgenticLaunchFacility publicLaunch = _createLaunch(projectOwner, agent, agent);
        MockToken publicToken = _publicTokenTo(address(publicLaunch), 100 ether);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, agent));
        publicLaunch.release(address(publicToken), nonAgent, 1 ether);

        vm.prank(projectOwner);
        publicLaunch.release(address(publicToken), nonAgent, 40 ether);
        assertEq(publicToken.balanceOf(nonAgent), 40 ether);
    }

    function testLaunchPublicERC20OwnerWorksAfterClose() public {
        AgenticLaunchFacility publicLaunch = _createLaunch(projectOwner, agent, agent);
        MockToken publicToken = _publicTokenTo(address(publicLaunch), 100 ether);
        vm.prank(projectOwner);
        publicLaunch.close();

        vm.prank(projectOwner);
        publicLaunch.release(address(publicToken), nonAgent, 10 ether);
        assertEq(publicToken.balanceOf(nonAgent), 10 ether);
    }

    function testLaunchGatedOperatorPathUnchangedWithPublicBranch() public {
        AgenticLaunchFacility publicLaunch = _createLaunch(projectOwner, agent, agent);
        AgenticToken gated = _fundLaunch(publicLaunch, 100 ether);

        vm.prank(agent);
        publicLaunch.release(address(gated), agent2, 25 ether);
        assertEq(gated.balanceOf(agent2), 25 ether);
    }

    function testLaunchReleaseRejectsNonAgentAndFacility() public {
        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.GatedRecipientNotAgent.selector, nonAgent));
        launch.release(address(token), nonAgent, 1 ether);

        AgenticVaultFacility other = _createVault(projectOwner);
        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticFacilityBase.FacilityRecipientNotAllowed.selector, address(other))
        );
        launch.release(address(token), address(other), 1 ether);
    }

    function testLaunchSetOperatorOnlyOwner() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, agent));
        launch.setOperator(agent2);

        vm.prank(projectOwner);
        launch.setOperator(agent2);
        assertEq(launch.operator(), agent2);

        vm.prank(projectOwner);
        vm.expectRevert(AgenticLaunchFacility.ZeroOperator.selector);
        launch.setOperator(address(0));
    }

    function testLaunchOwnerCanSetOperatorToItselfToDrive() public {
        AgenticLaunchFacility zeroOperator = _createLaunch(projectOwner, address(0), agent);
        AgenticToken otherToken = _fundLaunch(zeroOperator, 10 ether);

        vm.prank(projectOwner);
        zeroOperator.setOperator(projectOwner);

        vm.prank(projectOwner);
        zeroOperator.release(address(otherToken), agent, 5 ether);
        assertEq(otherToken.balanceOf(agent), 5 ether);
    }

    function testLaunchSetBeneficiaryAgentOnly() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, agent));
        launch.setBeneficiary(agent2);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotAgent.selector, nonAgent));
        launch.setBeneficiary(nonAgent);

        AgenticVaultFacility other = _createVault(projectOwner);
        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.FacilityNotAgent.selector, address(other)));
        launch.setBeneficiary(address(other));

        vm.prank(projectOwner);
        launch.setBeneficiary(agent2);
        assertEq(launch.beneficiary(), agent2);

        vm.prank(projectOwner);
        vm.expectRevert(AgenticLaunchFacility.ZeroBeneficiary.selector);
        launch.setBeneficiary(address(0));
    }

    function testLaunchCloseOnlyOwnerOrOperator() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticLaunchFacility.NotOwnerOrOperator.selector, agent));
        launch.close();

        vm.prank(projectOwner);
        launch.close();
        assertTrue(launch.closed());

        vm.prank(projectOwner);
        vm.expectRevert(AgenticLaunchFacility.AlreadyClosed.selector);
        launch.close();
    }

    function testLaunchOperatorCanClose() public {
        vm.prank(projectOwner);
        launch.setOperator(agent2);

        vm.prank(agent2);
        launch.close();
        assertTrue(launch.closed());
    }

    function testLaunchCloseRequiresAgentBeneficiary() public {
        AgenticLaunchFacility zeroBeneficiary = _createLaunch(projectOwner, projectOwner, address(0));
        vm.prank(projectOwner);
        vm.expectRevert(AgenticLaunchFacility.BeneficiaryNotSet.selector);
        zeroBeneficiary.close();
    }

    function testLaunchAfterCloseOnlyBeneficiaryOrMigrationTarget() public {
        vm.prank(projectOwner);
        launch.close();

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticLaunchFacility.ClosedRecipientNotBeneficiary.selector, agent2));
        launch.release(address(token), agent2, 1 ether);

        vm.prank(projectOwner);
        launch.release(address(token), agent, 100 ether);
        assertEq(token.balanceOf(agent), 100 ether);
    }

    function testLaunchBeforeCloseAnyAgentBuyer() public {
        vm.prank(projectOwner);
        launch.release(address(token), agent2, 100 ether);
        assertEq(token.balanceOf(agent2), 100 ether);
    }

    function testLaunchReleaseNativeOwnerOnly() public {
        vm.deal(address(launch), 2 ether);

        vm.prank(projectOwner);
        launch.releaseNative(payable(nonAgent), 1 ether);
        assertEq(nonAgent.balance, 1 ether);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, agent));
        launch.releaseNative(payable(agent), 1 ether);
    }

    function testLaunchReleaseRejectsZeroTokenAndRecipient() public {
        vm.prank(projectOwner);
        vm.expectRevert(AgenticFacilityBase.ZeroToken.selector);
        launch.release(address(0), agent, 1 ether);

        vm.prank(projectOwner);
        vm.expectRevert(AgenticFacilityBase.ZeroRecipient.selector);
        launch.release(address(token), address(0), 1 ether);
    }
}
