// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgenticFacilityBase} from "../../contracts/facility/AgenticFacilityBase.sol";
import {AgenticGameFacility} from "../../contracts/facility/AgenticGameFacility.sol";
import {AgenticVaultFacility} from "../../contracts/facility/AgenticVaultFacility.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";

import {MockToken} from "../mocks/MockToken.sol";
import {FacilityFixture} from "../helpers/FacilityFixture.sol";

contract AgenticGameFacilityTest is FacilityFixture {
    AgenticGameFacility internal gameFacility;
    AgenticToken internal token;

    function setUp() public {
        _deployFacilities();
        gameFacility = _defaultGame();
        token = _fundGame(gameFacility, 1_000 ether);
    }

    function testGameReleaseOperatorToAgent() public {
        vm.prank(projectOwner);
        gameFacility.release(address(token), agent, 200 ether);

        assertEq(token.balanceOf(agent), 200 ether);
        assertEq(token.balanceOf(address(gameFacility)), 800 ether);
    }

    function testGameRefundOperatorToAgent() public {
        vm.prank(projectOwner);
        gameFacility.refund(address(token), agent2, 150 ether);

        assertEq(token.balanceOf(agent2), 150 ether);
        assertEq(token.balanceOf(address(gameFacility)), 850 ether);
    }

    function testGameConsumeLocksWithoutSupplyChange() public {
        uint256 supplyBefore = token.totalSupply();
        vm.prank(projectOwner);
        gameFacility.consume(address(token), 400 ether);

        assertEq(token.balanceOf(address(gameFacility)), 1_000 ether);
        assertEq(gameFacility.consumed(address(token)), 400 ether);
        assertEq(gameFacility.availableOf(address(token)), 600 ether);
        assertEq(token.totalSupply(), supplyBefore);

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticGameFacility.InsufficientAvailable.selector, address(token), 601 ether, 600 ether
            )
        );
        gameFacility.release(address(token), agent, 601 ether);

        vm.prank(projectOwner);
        gameFacility.release(address(token), agent, 600 ether);
        assertEq(token.balanceOf(agent), 600 ether);
        assertEq(gameFacility.availableOf(address(token)), 0);

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticGameFacility.InsufficientAvailable.selector, address(token), 1 ether, 0)
        );
        gameFacility.refund(address(token), agent, 1 ether);
    }

    function testGameConsumeCannotExceedAvailable() public {
        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticGameFacility.InsufficientAvailable.selector, address(token), 1_001 ether, 1_000 ether
            )
        );
        gameFacility.consume(address(token), 1_001 ether);
    }

    function testGameConsumeRejectsZeroTokenAndAmount() public {
        vm.startPrank(projectOwner);
        vm.expectRevert(AgenticFacilityBase.ZeroToken.selector);
        gameFacility.consume(address(0), 1 ether);
        vm.expectRevert(AgenticGameFacility.ZeroAmount.selector);
        gameFacility.consume(address(token), 0);
        vm.stopPrank();
    }

    function testGameOnlyOperatorCanConsumeReleaseRefund() public {
        vm.startPrank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticGameFacility.NotOperator.selector, agent));
        gameFacility.consume(address(token), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(AgenticGameFacility.NotOperator.selector, agent));
        gameFacility.release(address(token), agent2, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(AgenticGameFacility.NotOperator.selector, agent));
        gameFacility.refund(address(token), agent2, 1 ether);
        vm.stopPrank();
    }

    function testGameReleaseAndRefundRejectNonAgentAndFacility() public {
        AgenticVaultFacility other = _createVault(projectOwner);
        vm.startPrank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.GatedRecipientNotAgent.selector, nonAgent));
        gameFacility.release(address(token), nonAgent, 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticFacilityBase.FacilityRecipientNotAllowed.selector, address(other))
        );
        gameFacility.release(address(token), address(other), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.GatedRecipientNotAgent.selector, nonAgent));
        gameFacility.refund(address(token), nonAgent, 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticFacilityBase.FacilityRecipientNotAllowed.selector, address(other))
        );
        gameFacility.refund(address(token), address(other), 1 ether);
        vm.stopPrank();
    }

    function testGameRejectsPublicTokens() public {
        MockToken publicToken = _publicTokenTo(address(gameFacility), 10 ether);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotGatedToken.selector, address(publicToken)));
        gameFacility.consume(address(publicToken), 1 ether);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotGatedToken.selector, address(publicToken)));
        gameFacility.release(address(publicToken), agent, 1 ether);
    }

    function testGameSetOperatorOnlyOwner() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, agent));
        gameFacility.setOperator(agent);

        vm.prank(projectOwner);
        gameFacility.setOperator(agent2);
        assertEq(gameFacility.operator(), agent2);

        vm.prank(projectOwner);
        vm.expectRevert(AgenticGameFacility.ZeroOperator.selector);
        gameFacility.setOperator(address(0));
    }

    function testGameOwnerCanSetOperatorToItselfToDrive() public {
        AgenticGameFacility zeroOperator = _createGame(projectOwner, address(0));
        AgenticToken otherToken = _fundGame(zeroOperator, 10 ether);

        vm.prank(projectOwner);
        zeroOperator.setOperator(projectOwner);

        vm.prank(projectOwner);
        zeroOperator.consume(address(otherToken), 4 ether);
        vm.prank(projectOwner);
        zeroOperator.release(address(otherToken), agent, 6 ether);
        assertEq(otherToken.balanceOf(agent), 6 ether);
    }

    function testGameLiquidateAlwaysReverts() public {
        vm.prank(projectOwner);
        vm.expectRevert(AgenticGameFacility.LiquidateNotSupported.selector);
        gameFacility.liquidate(address(token), agent, 1 ether);
    }

    function testGameReleaseRejectsZeroTokenAndRecipient() public {
        vm.startPrank(projectOwner);
        vm.expectRevert(AgenticFacilityBase.ZeroToken.selector);
        gameFacility.release(address(0), agent, 1 ether);
        vm.expectRevert(AgenticFacilityBase.ZeroRecipient.selector);
        gameFacility.release(address(token), address(0), 1 ether);
        vm.stopPrank();
    }
}
