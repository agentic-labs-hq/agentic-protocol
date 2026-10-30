// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgenticFacilityBase} from "../../contracts/facility/AgenticFacilityBase.sol";
import {AgenticEscrowFacility} from "../../contracts/facility/AgenticEscrowFacility.sol";
import {AgenticVaultFacility} from "../../contracts/facility/AgenticVaultFacility.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";

import {MockToken} from "../mocks/MockToken.sol";
import {FacilityFixture} from "../helpers/FacilityFixture.sol";

contract AgenticEscrowFacilityTest is FacilityFixture {
    AgenticEscrowFacility internal escrow;
    AgenticToken internal token;

    function setUp() public {
        _deployFacilities();
        escrow = _defaultEscrow();
        token = _gatedToAgent(agent, 1_000 ether);
        vm.prank(agent);
        token.approve(address(escrow), type(uint256).max);
    }

    function _deposit(uint256 amount) internal {
        vm.prank(agent);
        escrow.deposit(address(token), amount);
    }

    function testEscrowDepositOnlyDepositor() public {
        vm.prank(agent2);
        vm.expectRevert(abi.encodeWithSelector(AgenticEscrowFacility.NotDepositor.selector, agent2));
        escrow.deposit(address(token), 1 ether);

        _deposit(500 ether);
        assertEq(token.balanceOf(address(escrow)), 500 ether);
        assertEq(uint8(escrow.stateOf(address(token))), uint8(AgenticEscrowFacility.EscrowState.FUNDED));
        assertTrue(escrow.hasDeposit());
    }

    function testEscrowReleaseByBeneficiaryToAgent() public {
        _deposit(500 ether);

        vm.prank(agent);
        escrow.release(address(token), agent2, 500 ether);

        assertEq(token.balanceOf(agent2), 500 ether);
        assertEq(uint8(escrow.stateOf(address(token))), uint8(AgenticEscrowFacility.EscrowState.RELEASED));
    }

    function testEscrowReleaseByArbiterToAgent() public {
        _deposit(500 ether);

        vm.prank(projectOwner);
        escrow.release(address(token), agent2, 500 ether);
        assertEq(token.balanceOf(agent2), 500 ether);
    }

    function testEscrowRefundByDepositorToAgent() public {
        _deposit(500 ether);

        vm.prank(agent);
        escrow.refund(address(token), agent, 500 ether);
        assertEq(token.balanceOf(agent), 1_000 ether);
        assertEq(uint8(escrow.stateOf(address(token))), uint8(AgenticEscrowFacility.EscrowState.REFUNDED));
    }

    function testEscrowRefundByArbiterToAgent() public {
        _deposit(500 ether);

        vm.prank(projectOwner);
        escrow.refund(address(token), agent2, 500 ether);
        assertEq(token.balanceOf(agent2), 500 ether);
    }

    function testEscrowWrongRoleReleaseAndRefund() public {
        _deposit(500 ether);

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticEscrowFacility.NotBeneficiaryOrArbiter.selector, nonAgent));
        escrow.release(address(token), agent2, 1 ether);

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticEscrowFacility.NotDepositorOrArbiter.selector, nonAgent));
        escrow.refund(address(token), agent2, 1 ether);

        vm.prank(agent2);
        vm.expectRevert(abi.encodeWithSelector(AgenticEscrowFacility.NotBeneficiaryOrArbiter.selector, agent2));
        escrow.release(address(token), agent2, 1 ether);
    }

    function testEscrowStateMachine() public {
        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticEscrowFacility.InvalidEscrowState.selector,
                address(token),
                AgenticEscrowFacility.EscrowState.NONE
            )
        );
        escrow.release(address(token), agent2, 1 ether);

        _deposit(500 ether);

        vm.prank(agent);
        escrow.release(address(token), agent2, 500 ether);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticEscrowFacility.InvalidEscrowState.selector,
                address(token),
                AgenticEscrowFacility.EscrowState.RELEASED
            )
        );
        escrow.refund(address(token), agent, 500 ether);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticEscrowFacility.InvalidEscrowState.selector,
                address(token),
                AgenticEscrowFacility.EscrowState.RELEASED
            )
        );
        escrow.deposit(address(token), 1 ether);
    }

    function testEscrowRefundAfterRefundReverts() public {
        _deposit(500 ether);

        vm.prank(agent);
        escrow.refund(address(token), agent, 500 ether);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticEscrowFacility.InvalidEscrowState.selector,
                address(token),
                AgenticEscrowFacility.EscrowState.REFUNDED
            )
        );
        escrow.refund(address(token), agent, 1 ether);
    }

    function testEscrowSetArbiterOnlyOwner() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, agent));
        escrow.setArbiter(agent);

        vm.prank(projectOwner);
        escrow.setArbiter(agent2);
        assertEq(escrow.arbiter(), agent2);

        vm.prank(projectOwner);
        vm.expectRevert(AgenticEscrowFacility.ZeroArbiter.selector);
        escrow.setArbiter(address(0));
    }

    function testEscrowSetBeneficiaryOnlyOwnerBeforeDeposit() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, agent));
        escrow.setBeneficiary(agent2);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotAgent.selector, nonAgent));
        escrow.setBeneficiary(nonAgent);

        AgenticVaultFacility other = _createVault(projectOwner);
        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.FacilityNotAgent.selector, address(other)));
        escrow.setBeneficiary(address(other));

        vm.prank(projectOwner);
        escrow.setBeneficiary(agent2);
        assertEq(escrow.beneficiary(), agent2);

        _deposit(1 ether);

        vm.prank(projectOwner);
        vm.expectRevert(AgenticEscrowFacility.BeneficiaryAfterDeposit.selector);
        escrow.setBeneficiary(agent);
    }

    function testEscrowReleaseRejectsNonAgentAndFacility() public {
        _deposit(500 ether);
        AgenticVaultFacility other = _createVault(projectOwner);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.GatedRecipientNotAgent.selector, nonAgent));
        escrow.release(address(token), nonAgent, 1 ether);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticFacilityBase.FacilityRecipientNotAllowed.selector, address(other))
        );
        escrow.release(address(token), address(other), 1 ether);
    }

    function testEscrowRejectsPublicTokenReleaseFromDirectBalance() public {
        MockToken publicToken = _publicTokenTo(address(escrow), 10 ether);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotGatedToken.selector, address(publicToken)));
        escrow.release(address(publicToken), agent, 1 ether);
    }

    function testEscrowFirstDepositFixesDepositor() public {
        AgenticEscrowFacility openEscrow = _createEscrow(projectOwner, projectOwner, agent, address(0));
        AgenticToken openToken = _gatedToAgent(agent, 100 ether);
        AgenticToken otherToken = _gatedToAgent(agent2, 100 ether);

        vm.prank(agent);
        openToken.approve(address(openEscrow), type(uint256).max);
        vm.prank(agent2);
        otherToken.approve(address(openEscrow), type(uint256).max);

        vm.prank(agent2);
        openEscrow.deposit(address(otherToken), 10 ether);
        assertEq(openEscrow.depositor(), agent2);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticEscrowFacility.NotDepositor.selector, agent));
        openEscrow.deposit(address(openToken), 10 ether);
    }

    function testEscrowFirstDepositRequiresAgent() public {
        AgenticEscrowFacility openEscrow = _createEscrow(projectOwner, projectOwner, agent, address(0));
        AgenticToken gated = _gatedToAgent(agent, 10 ether);

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotAgent.selector, nonAgent));
        openEscrow.deposit(address(gated), 1 ether);
    }

    function testEscrowRejectsPublicTokenDeposit() public {
        MockToken publicToken = _publicTokenTo(agent, 10 ether);
        vm.prank(agent);
        publicToken.approve(address(escrow), type(uint256).max);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotGatedToken.selector, address(publicToken)));
        escrow.deposit(address(publicToken), 1 ether);
    }

    function testEscrowConsumeAndLiquidateAlwaysRevert() public {
        vm.prank(projectOwner);
        vm.expectRevert(AgenticEscrowFacility.ConsumeNotSupported.selector);
        escrow.consume(address(token), 1 ether);

        vm.prank(projectOwner);
        vm.expectRevert(AgenticEscrowFacility.LiquidateNotSupported.selector);
        escrow.liquidate(address(token), agent, 1 ether);
    }

    function testEscrowDepositRejectsZero() public {
        vm.prank(agent);
        vm.expectRevert(AgenticFacilityBase.ZeroToken.selector);
        escrow.deposit(address(0), 1 ether);

        vm.prank(agent);
        vm.expectRevert(AgenticEscrowFacility.ZeroAmount.selector);
        escrow.deposit(address(token), 0);
    }

    function testEscrowMultiTokenIndependentState() public {
        AgenticToken second = _gatedToAgent(agent, 200 ether);
        vm.prank(agent);
        second.approve(address(escrow), type(uint256).max);

        _deposit(100 ether);
        vm.prank(agent);
        escrow.deposit(address(second), 50 ether);

        vm.prank(agent);
        escrow.release(address(token), agent2, 100 ether);

        assertEq(uint8(escrow.stateOf(address(token))), uint8(AgenticEscrowFacility.EscrowState.RELEASED));
        assertEq(uint8(escrow.stateOf(address(second))), uint8(AgenticEscrowFacility.EscrowState.FUNDED));

        vm.prank(projectOwner);
        escrow.refund(address(second), agent, 50 ether);
        assertEq(uint8(escrow.stateOf(address(second))), uint8(AgenticEscrowFacility.EscrowState.REFUNDED));
    }
}
