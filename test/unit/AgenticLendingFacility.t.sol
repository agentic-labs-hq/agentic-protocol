// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgenticFacilityBase} from "../../contracts/facility/AgenticFacilityBase.sol";
import {AgenticLendingFacility} from "../../contracts/facility/AgenticLendingFacility.sol";
import {AgenticVaultFacility} from "../../contracts/facility/AgenticVaultFacility.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";

import {MockToken} from "../mocks/MockToken.sol";
import {FacilityFixture} from "../helpers/FacilityFixture.sol";

contract AgenticLendingFacilityTest is FacilityFixture {
    AgenticLendingFacility internal lending;
    AgenticToken internal token;

    function setUp() public {
        _deployFacilities();
        lending = _defaultLending();
        token = _gatedToAgent(agent, 1_000 ether);
        vm.prank(agent);
        token.approve(address(lending), type(uint256).max);
    }

    function _deposit(uint256 amount) internal {
        vm.prank(agent);
        lending.deposit(address(token), amount);
    }

    function testLendingDepositOnlyLender() public {
        vm.prank(agent2);
        vm.expectRevert(abi.encodeWithSelector(AgenticLendingFacility.NotLender.selector, agent2));
        lending.deposit(address(token), 1 ether);

        _deposit(1_000 ether);
        assertEq(token.balanceOf(address(lending)), 1_000 ether);
        assertEq(lending.totalDeposited(address(token)), 1_000 ether);
        assertEq(lending.availableOf(address(token)), 1_000 ether);
    }

    function testLendingBorrowOnlyBorrower() public {
        _deposit(1_000 ether);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticLendingFacility.NotBorrower.selector, agent));
        lending.borrow(address(token), 1 ether);

        vm.prank(agent2);
        lending.borrow(address(token), 400 ether);
        assertEq(token.balanceOf(agent2), 400 ether);
        assertEq(lending.totalBorrowed(address(token)), 400 ether);
        assertEq(lending.availableOf(address(token)), 600 ether);
    }

    function testLendingBorrowCannotExceedLiquidity() public {
        _deposit(1_000 ether);
        vm.prank(agent2);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticLendingFacility.InsufficientLiquidity.selector, address(token), 1_001 ether, 1_000 ether
            )
        );
        lending.borrow(address(token), 1_001 ether);
    }

    function testLendingRepayOnlyBorrower() public {
        _deposit(1_000 ether);
        vm.prank(agent2);
        lending.borrow(address(token), 400 ether);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticLendingFacility.NotBorrower.selector, agent));
        lending.repay(address(token), 100 ether);

        vm.prank(agent2);
        token.approve(address(lending), type(uint256).max);
        vm.prank(agent2);
        lending.repay(address(token), 100 ether);

        assertEq(lending.totalBorrowed(address(token)), 300 ether);
        assertEq(token.balanceOf(address(lending)), 700 ether);
    }

    function testLendingRepayCannotExceedDebt() public {
        _deposit(1_000 ether);
        vm.prank(agent2);
        lending.borrow(address(token), 400 ether);
        vm.prank(agent2);
        token.approve(address(lending), type(uint256).max);

        vm.prank(agent2);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticLendingFacility.RepayExceedsDebt.selector, address(token), 401 ether, 400 ether
            )
        );
        lending.repay(address(token), 401 ether);
    }

    function testLendingWithdrawOnlyLender() public {
        _deposit(1_000 ether);

        vm.prank(agent2);
        vm.expectRevert(abi.encodeWithSelector(AgenticLendingFacility.NotLender.selector, agent2));
        lending.withdraw(address(token), agent2, 1 ether);

        vm.prank(agent);
        lending.withdraw(address(token), agent2, 500 ether);
        assertEq(token.balanceOf(agent2), 500 ether);
        assertEq(lending.totalDeposited(address(token)), 500 ether);
    }

    function testLendingWithdrawCannotExceedAvailable() public {
        _deposit(1_000 ether);
        vm.prank(agent2);
        lending.borrow(address(token), 400 ether);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticLendingFacility.InsufficientWithdrawal.selector, address(token), 601 ether, 600 ether
            )
        );
        lending.withdraw(address(token), agent2, 601 ether);
    }

    function testLendingLiquidateOnlyKeeperOrOracle() public {
        _deposit(1_000 ether);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticLendingFacility.NotKeeperOrOracle.selector, agent));
        lending.liquidate(address(token), agent2, 1 ether);

        vm.prank(projectOwner);
        lending.liquidate(address(token), agent2, 100 ether);
        assertEq(token.balanceOf(agent2), 100 ether);

        vm.prank(projectOwner);
        lending.setOracle(agent);
        vm.prank(agent);
        lending.liquidate(address(token), agent2, 100 ether);
        assertEq(token.balanceOf(agent2), 200 ether);
    }

    function testLendingSetKeeperAndOracleOnlyOwner() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, agent));
        lending.setKeeper(agent);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, agent));
        lending.setOracle(agent);

        vm.startPrank(projectOwner);
        lending.setKeeper(agent);
        lending.setOracle(agent2);
        assertEq(lending.keeper(), agent);
        assertEq(lending.oracle(), agent2);

        vm.expectRevert(AgenticLendingFacility.ZeroKeeper.selector);
        lending.setKeeper(address(0));
        vm.expectRevert(AgenticLendingFacility.ZeroOracle.selector);
        lending.setOracle(address(0));
        vm.stopPrank();
    }

    function testLendingOwnerCanSetKeeperToItselfToDrive() public {
        _deposit(1_000 ether);
        vm.prank(projectOwner);
        lending.setKeeper(projectOwner);
        vm.prank(projectOwner);
        lending.liquidate(address(token), agent, 50 ether);
        assertEq(token.balanceOf(agent), 50 ether);
    }

    function testLendingDepositBorrowRepayWithdrawPath() public {
        _deposit(1_000 ether);
        vm.prank(agent2);
        lending.borrow(address(token), 400 ether);
        vm.prank(agent2);
        token.approve(address(lending), type(uint256).max);
        vm.prank(agent2);
        lending.repay(address(token), 100 ether);
        vm.prank(agent);
        lending.withdraw(address(token), agent, 500 ether);

        assertEq(lending.totalDeposited(address(token)), 500 ether);
        assertEq(lending.totalBorrowed(address(token)), 300 ether);
        assertEq(lending.availableOf(address(token)), 200 ether);
        assertEq(token.balanceOf(address(lending)), 200 ether);
    }

    function testLendingFirstDepositAndBorrowFixRoles() public {
        AgenticLendingFacility openLending =
            _createLending(projectOwner, projectOwner, projectOwner, address(0), address(0));
        AgenticToken openToken = _gatedToAgent(agent, 1_000 ether);
        vm.prank(agent);
        openToken.approve(address(openLending), type(uint256).max);

        vm.prank(agent);
        openLending.deposit(address(openToken), 500 ether);
        assertEq(openLending.lender(), agent);

        vm.prank(agent2);
        openLending.borrow(address(openToken), 100 ether);
        assertEq(openLending.borrower(), agent2);
    }

    function testLendingFirstDepositRequiresAgent() public {
        AgenticLendingFacility openLending =
            _createLending(projectOwner, projectOwner, projectOwner, address(0), agent2);
        AgenticToken gated = _gatedToAgent(agent, 10 ether);

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotAgent.selector, nonAgent));
        openLending.deposit(address(gated), 1 ether);
    }

    function testLendingRejectsPublicTokenDeposit() public {
        MockToken publicToken = _publicTokenTo(agent, 10 ether);
        vm.prank(agent);
        publicToken.approve(address(lending), type(uint256).max);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotGatedToken.selector, address(publicToken)));
        lending.deposit(address(publicToken), 1 ether);
    }

    function testLendingRejectsPublicTokenWithdrawFromDirectBalance() public {
        MockToken publicToken = _publicTokenTo(address(lending), 10 ether);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotGatedToken.selector, address(publicToken)));
        lending.withdraw(address(publicToken), agent, 1 ether);
    }

    function testLendingFirstBorrowRequiresAgent() public {
        AgenticLendingFacility openLending = _createLending(projectOwner, projectOwner, projectOwner, agent, address(0));
        AgenticToken openToken = _gatedToAgent(agent, 100 ether);
        vm.prank(agent);
        openToken.approve(address(openLending), type(uint256).max);
        vm.prank(agent);
        openLending.deposit(address(openToken), 100 ether);
        vm.deal(nonAgent, 1 ether);

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotAgent.selector, nonAgent));
        openLending.borrow(address(openToken), 1 ether);
    }

    function testLendingBorrowWithdrawLiquidateRejectNonAgentAndFacility() public {
        _deposit(1_000 ether);
        AgenticVaultFacility other = _createVault(projectOwner);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.GatedRecipientNotAgent.selector, nonAgent));
        lending.withdraw(address(token), nonAgent, 1 ether);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticFacilityBase.FacilityRecipientNotAllowed.selector, address(other))
        );
        lending.withdraw(address(token), address(other), 1 ether);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.GatedRecipientNotAgent.selector, nonAgent));
        lending.liquidate(address(token), nonAgent, 1 ether);

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticFacilityBase.FacilityRecipientNotAllowed.selector, address(other))
        );
        lending.liquidate(address(token), address(other), 1 ether);
    }

    function testLendingConsumeReleaseRefundAlwaysRevert() public {
        vm.startPrank(projectOwner);
        vm.expectRevert(AgenticLendingFacility.ConsumeNotSupported.selector);
        lending.consume(address(token), 1 ether);
        vm.expectRevert(AgenticLendingFacility.ReleaseNotSupported.selector);
        lending.release(address(token), agent, 1 ether);
        vm.expectRevert(AgenticLendingFacility.RefundNotSupported.selector);
        lending.refund(address(token), agent, 1 ether);
        vm.stopPrank();
    }

    function testLendingRejectsZeroTokenAndAmount() public {
        vm.startPrank(agent);
        vm.expectRevert(AgenticFacilityBase.ZeroToken.selector);
        lending.deposit(address(0), 1 ether);
        vm.expectRevert(AgenticLendingFacility.ZeroAmount.selector);
        lending.deposit(address(token), 0);
        vm.stopPrank();
    }
}
