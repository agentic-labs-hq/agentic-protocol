// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgenticEscrowFacility} from "../../contracts/facility/AgenticEscrowFacility.sol";
import {AgenticGameFacility} from "../../contracts/facility/AgenticGameFacility.sol";
import {AgenticLaunchFacility} from "../../contracts/facility/AgenticLaunchFacility.sol";
import {AgenticLendingFacility} from "../../contracts/facility/AgenticLendingFacility.sol";
import {AgenticVaultFacility} from "../../contracts/facility/AgenticVaultFacility.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";

import {AgenticFacilityBase} from "../../contracts/facility/AgenticFacilityBase.sol";
import {FacilityFixture} from "../helpers/FacilityFixture.sol";

/// @notice Proves that PURPOSE/CUSTODY owners have no project-withdrawal path
/// outside their function-level role. Owner can change roles, but only the role
/// holder can move gated assets, and only to agents/migration targets.
contract FacilityProjectWithdrawalTest is FacilityFixture {
    function setUp() public {
        _deployFacilities();
    }

    function testVaultOwnerCannotSendGatedToItself() public {
        AgenticVaultFacility vault = _defaultVault();
        AgenticToken token = _fundVault(vault, 100 ether);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.GatedRecipientNotAgent.selector, projectOwner));
        vault.release(address(token), projectOwner, 1 ether);
    }

    function testLaunchOwnerWithoutOperatorRoleCannotSell() public {
        AgenticLaunchFacility launch = _createLaunch(projectOwner, agent, agent);
        AgenticToken token = _fundLaunch(launch, 100 ether);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticLaunchFacility.NotOperator.selector, projectOwner));
        launch.release(address(token), agent2, 1 ether);
    }

    function testGameOwnerWithoutOperatorRoleCannotReleaseOrRefund() public {
        AgenticGameFacility game = _createGame(projectOwner, agent);
        AgenticToken token = _fundGame(game, 100 ether);

        vm.startPrank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticGameFacility.NotOperator.selector, projectOwner));
        game.release(address(token), agent2, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(AgenticGameFacility.NotOperator.selector, projectOwner));
        game.refund(address(token), agent2, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(AgenticGameFacility.NotOperator.selector, projectOwner));
        game.consume(address(token), 1 ether);
        vm.stopPrank();
    }

    function testEscrowOwnerWithoutRoleCannotReleaseOrRefund() public {
        AgenticEscrowFacility escrow = _createEscrow(projectOwner, agent, agent2, agent);
        AgenticToken token = _gatedToAgent(agent, 100 ether);
        vm.prank(agent);
        token.approve(address(escrow), type(uint256).max);
        vm.prank(agent);
        escrow.deposit(address(token), 50 ether);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticEscrowFacility.NotBeneficiaryOrArbiter.selector, projectOwner));
        escrow.release(address(token), agent2, 1 ether);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticEscrowFacility.NotDepositorOrArbiter.selector, projectOwner));
        escrow.refund(address(token), projectOwner, 1 ether);
    }

    function testLendingOwnerWithoutRoleCannotWithdrawDeposits() public {
        AgenticLendingFacility lending = _createLending(projectOwner, agent, agent, agent, agent2);
        AgenticToken token = _gatedToAgent(agent, 100 ether);
        vm.prank(agent);
        token.approve(address(lending), type(uint256).max);
        vm.prank(agent);
        lending.deposit(address(token), 50 ether);

        vm.startPrank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticLendingFacility.NotLender.selector, projectOwner));
        lending.withdraw(address(token), projectOwner, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(AgenticLendingFacility.NotKeeperOrOracle.selector, projectOwner));
        lending.liquidate(address(token), projectOwner, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(AgenticLendingFacility.NotBorrower.selector, projectOwner));
        lending.borrow(address(token), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(AgenticLendingFacility.NotBorrower.selector, projectOwner));
        lending.repay(address(token), 1 ether);
        vm.stopPrank();
    }
}
