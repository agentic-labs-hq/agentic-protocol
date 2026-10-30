// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Governance2Step} from "../../contracts/common/Governance2Step.sol";
import {AgenticTreasury} from "../../contracts/treasury/AgenticTreasury.sol";

import {TreasuryFixture} from "../helpers/TreasuryFixture.sol";
import {MockAgenticToken} from "../mocks/MockAgenticToken.sol";
import {MockSwapRouter} from "../mocks/MockSwapRouter.sol";

/// @notice AgenticTreasury unit tests: wiring, governance, transfer,
/// swap and distribution behavior.
contract AgenticTreasuryTest is TreasuryFixture {
    uint256 internal constant MAX_BATCH_LIMIT_FOR_TEST = 256;

    event TreasuryTransfer(address indexed token, address indexed to, uint256 amount);
    event TreasurySwap(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event GovernanceTransferStarted(address indexed current, address indexed pending);
    event GovernanceTransferred(address indexed previous, address indexed newGovernance);

    function setUp() public {
        _deployTreasury();
    }

    // ------------------------------------------------------------- constructor

    function testInitialStateAndWiring() public view {
        assertEq(treasury.governance(), address(this));
        assertEq(treasury.pendingGovernance(), address(0));
        assertEq(treasury.assetRegistry(), address(assetRegistry));
        assertEq(treasury.facilityRegistry(), address(venueRegistry));
        assertEq(treasury.router(), address(router));
        assertEq(treasury.maxDistributionBatch(), MAX_BATCH);
        assertEq(treasury.MAX_DISTRIBUTION_BATCH_LIMIT(), 256);
    }

    function testConstructorRejectsZeroGovernance() public {
        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        new AgenticTreasury(address(assetRegistry), address(venueRegistry), address(router), MAX_BATCH, address(0));
    }

    function testConstructorRejectsZeroAssetRegistry() public {
        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        new AgenticTreasury(address(0), address(venueRegistry), address(router), MAX_BATCH, address(this));
    }

    function testConstructorRejectsZeroFacilityRegistry() public {
        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        new AgenticTreasury(address(assetRegistry), address(0), address(router), MAX_BATCH, address(this));
    }

    function testConstructorRejectsZeroRouter() public {
        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        new AgenticTreasury(address(assetRegistry), address(venueRegistry), address(0), MAX_BATCH, address(this));
    }

    function testConstructorRejectsNonContractAssetRegistry() public {
        address eoa = address(0x1234);
        vm.expectRevert(abi.encodeWithSelector(AgenticTreasury.NotContract.selector, eoa));
        new AgenticTreasury(eoa, address(venueRegistry), address(router), MAX_BATCH, address(this));
    }

    function testConstructorRejectsNonContractFacilityRegistry() public {
        address eoa = address(0x1234);
        vm.expectRevert(abi.encodeWithSelector(AgenticTreasury.NotContract.selector, eoa));
        new AgenticTreasury(address(assetRegistry), eoa, address(router), MAX_BATCH, address(this));
    }

    function testConstructorRejectsNonContractRouter() public {
        address eoa = address(0x1234);
        vm.expectRevert(abi.encodeWithSelector(AgenticTreasury.NotContract.selector, eoa));
        new AgenticTreasury(address(assetRegistry), address(venueRegistry), eoa, MAX_BATCH, address(this));
    }

    function testConstructorRejectsZeroMaxDistributionBatch() public {
        vm.expectRevert(
            abi.encodeWithSelector(AgenticTreasury.InvalidDistributionBatch.selector, 0, MAX_BATCH_LIMIT_FOR_TEST)
        );
        new AgenticTreasury(address(assetRegistry), address(venueRegistry), address(router), 0, address(this));
    }

    function testConstructorRejectsMaxDistributionBatchAboveLimit() public {
        uint256 tooLarge = 257;
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticTreasury.InvalidDistributionBatch.selector, tooLarge, MAX_BATCH_LIMIT_FOR_TEST
            )
        );
        new AgenticTreasury(address(assetRegistry), address(venueRegistry), address(router), tooLarge, address(this));
    }

    function testConstructorAcceptsBatchBoundaryValues() public {
        AgenticTreasury lower =
            new AgenticTreasury(address(assetRegistry), address(venueRegistry), address(router), 1, address(this));
        AgenticTreasury upper = new AgenticTreasury(
            address(assetRegistry), address(venueRegistry), address(router), MAX_BATCH_LIMIT_FOR_TEST, address(this)
        );

        assertEq(lower.maxDistributionBatch(), 1);
        assertEq(upper.maxDistributionBatch(), MAX_BATCH_LIMIT_FOR_TEST);
    }

    // -------------------------------------------------------------- governance

    function testGovernanceTwoStep() public {
        address newGov = address(0xC0FFEE);

        vm.expectEmit(true, true, false, true, address(treasury));
        emit GovernanceTransferStarted(address(this), newGov);
        treasury.transferGovernance(newGov);
        assertEq(treasury.governance(), address(this));
        assertEq(treasury.pendingGovernance(), newGov);

        vm.expectEmit(true, true, false, true, address(treasury));
        emit GovernanceTransferred(address(this), newGov);
        vm.prank(newGov);
        treasury.acceptGovernance();

        assertEq(treasury.governance(), newGov);
        assertEq(treasury.pendingGovernance(), address(0));

        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, address(this)));
        treasury.transferToken(address(publicToken), nonAgent, 1);

        vm.prank(newGov);
        treasury.transferToken(address(publicToken), nonAgent, 1);
        assertEq(publicToken.balanceOf(nonAgent), 1);
    }

    function testTransferGovernanceOnlyGovernance() public {
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonGov));
        treasury.transferGovernance(nonGov);
    }

    function testTransferGovernanceRejectsZero() public {
        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        treasury.transferGovernance(address(0));
    }

    function testTransferGovernanceRejectsUnchanged() public {
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.GovernanceUnchanged.selector, address(this)));
        treasury.transferGovernance(address(this));
    }

    function testAcceptGovernanceOnlyPending() public {
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotPendingGovernance.selector, nonGov));
        treasury.acceptGovernance();
    }

    // ----------------------------------------------------------- transferToken

    function testTransferTokenGatedToAgent() public {
        uint256 amount = 1_000e18;

        vm.expectEmit(true, true, false, true, address(treasury));
        emit TreasuryTransfer(address(gatedToken), agent, amount);
        treasury.transferToken(address(gatedToken), agent, amount);

        assertEq(gatedToken.balanceOf(agent), amount);
        assertEq(gatedToken.balanceOf(address(treasury)), INITIAL_BALANCE - amount);
    }

    function testTransferTokenGatedToAgent2() public {
        uint256 amount = 5e18;
        treasury.transferToken(address(gatedToken), agent2, amount);

        assertEq(gatedToken.balanceOf(agent2), amount);
    }

    function testTransferTokenGatedToNonAgentReverts() public {
        uint256 before = gatedToken.balanceOf(nonAgent);

        vm.expectRevert(
            abi.encodeWithSelector(AgenticTreasury.GatedRecipientNotAgent.selector, address(gatedToken), nonAgent)
        );
        treasury.transferToken(address(gatedToken), nonAgent, 1e18);

        assertEq(gatedToken.balanceOf(nonAgent), before);
        assertEq(gatedToken.balanceOf(address(treasury)), INITIAL_BALANCE);
    }

    function testTransferTokenGatedToFacilityReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticTreasury.GatedRecipientNotAgent.selector, address(gatedToken), address(replacement)
            )
        );
        treasury.transferToken(address(gatedToken), address(replacement), 1e18);
    }

    function testTransferTokenGatedToRevokedFacilityWithAgentIdReverts() public {
        policy.setMember(address(replacement), true);
        policy.setRevoked(address(replacement), true);

        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticTreasury.GatedRecipientNotAgent.selector, address(gatedToken), address(replacement)
            )
        );
        treasury.transferToken(address(gatedToken), address(replacement), 1e18);
    }

    function testTransferTokenPublicToNonAgent() public {
        uint256 amount = 7e18;

        vm.expectEmit(true, true, false, true, address(treasury));
        emit TreasuryTransfer(address(publicToken), nonAgent, amount);
        treasury.transferToken(address(publicToken), nonAgent, amount);

        assertEq(publicToken.balanceOf(nonAgent), amount);
    }

    function testTransferTokenOnlyGovernanceGated() public {
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonGov));
        treasury.transferToken(address(gatedToken), agent, 1e18);
    }

    function testTransferTokenOnlyGovernancePublic() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, agent));
        treasury.transferToken(address(publicToken), nonAgent, 1e18);
    }

    function testTransferTokenZeroTokenReverts() public {
        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        treasury.transferToken(address(0), agent, 1e18);
    }

    function testTransferTokenZeroRecipientReverts() public {
        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        treasury.transferToken(address(gatedToken), address(0), 1e18);
    }

    function testTransferTokenZeroAmountAllowed() public {
        uint256 before = gatedToken.balanceOf(agent);

        vm.expectEmit(true, true, false, true, address(treasury));
        emit TreasuryTransfer(address(gatedToken), agent, 0);
        treasury.transferToken(address(gatedToken), agent, 0);

        assertEq(gatedToken.balanceOf(agent), before);
        assertEq(gatedToken.balanceOf(address(treasury)), INITIAL_BALANCE);
    }

    function testTransferTokenExceedsBalanceReverts() public {
        vm.expectRevert();
        treasury.transferToken(address(gatedToken), agent, INITIAL_BALANCE + 1);
    }

    // ---------------------------------------------------------- transferNative

    function testTransferNativeToNonAgent() public {
        _fundNative();
        uint256 amount = 3e18;

        vm.expectEmit(true, true, false, true, address(treasury));
        emit TreasuryTransfer(address(0), nonAgent, amount);
        treasury.transferNative(payable(nonAgent), amount);

        assertEq(nonAgent.balance, amount);
    }

    function testTransferNativeOnlyGovernance() public {
        _fundNative();
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonGov));
        treasury.transferNative(payable(nonAgent), 1e18);
    }

    function testTransferNativeZeroRecipientReverts() public {
        _fundNative();
        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        treasury.transferNative(payable(address(0)), 1e18);
    }

    function testTransferNativeInsufficientBalanceReverts() public {
        vm.deal(address(treasury), 1);
        vm.expectRevert();
        treasury.transferNative(payable(nonAgent), 2);
    }

    function testReceiveAcceptsNative() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(treasury).call{value: 1 ether}("");

        assertTrue(ok);
        assertEq(address(treasury).balance, 1 ether);
    }

    // ---------------------------------------------------------------- swap

    function testSwapPublicTokensSucceeds() public {
        router.setAmountOut(500e18);

        uint256 amountOut = treasury.swapExactInputSingle(
            address(publicToken), address(publicTokenB), 3000, 100e18, 490e18, _deadline()
        );

        assertEq(amountOut, 500e18);
        assertEq(router.callCount(), 1);
        assertEq(router.lastRecipient(), address(treasury));
        assertEq(publicToken.balanceOf(address(treasury)), INITIAL_BALANCE);
    }

    function testSwapRouterReceivesExpectedParams() public {
        router.setAmountOut(123e18);
        router.setPullTokens(false);
        uint256 deadline = _deadline();

        treasury.swapExactInputSingle(address(publicToken), address(publicTokenB), 500, 42e18, 7e18, deadline);

        assertEq(router.lastTokenIn(), address(publicToken));
        assertEq(router.lastTokenOut(), address(publicTokenB));
        assertEq(uint256(router.lastFee()), 500);
        assertEq(router.lastRecipient(), address(treasury));
        assertEq(router.lastDeadline(), deadline);
        assertEq(router.lastAmountIn(), 42e18);
        assertEq(router.lastAmountOutMinimum(), 7e18);
        assertEq(uint256(router.lastSqrtPriceLimitX96()), 0);
        assertEq(router.lastAllowanceSeen(), 42e18);
    }

    function testSwapApprovalSetAndReset() public {
        router.setAmountOut(1e18);
        router.setPullTokens(false);

        treasury.swapExactInputSingle(address(publicToken), address(publicTokenB), 3000, 9e18, 0, _deadline());

        assertEq(router.lastAllowanceSeen(), 9e18);
        assertEq(publicToken.allowance(address(treasury), address(router)), 0);
    }

    function testSwapGatedTokenInReverts() public {
        vm.expectRevert(AgenticTreasury.GatedSwapNotAllowed.selector);
        treasury.swapExactInputSingle(address(gatedToken), address(publicToken), 3000, 1e18, 0, _deadline());

        assertEq(router.callCount(), 0);
    }

    function testSwapGatedTokenOutReverts() public {
        vm.expectRevert(AgenticTreasury.GatedSwapNotAllowed.selector);
        treasury.swapExactInputSingle(address(publicToken), address(gatedToken), 3000, 1e18, 0, _deadline());

        assertEq(router.callCount(), 0);
    }

    function testSwapBothGatedReverts() public {
        MockAgenticToken gatedTokenB = new MockAgenticToken(address(policy));
        assetRegistry.setRegistered(address(gatedTokenB), true);

        vm.expectRevert(AgenticTreasury.GatedSwapNotAllowed.selector);
        treasury.swapExactInputSingle(address(gatedToken), address(gatedTokenB), 3000, 1e18, 0, _deadline());
    }

    function testSwapZeroTokenInReverts() public {
        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        treasury.swapExactInputSingle(address(0), address(publicToken), 3000, 1e18, 0, _deadline());
    }

    function testSwapZeroTokenOutReverts() public {
        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        treasury.swapExactInputSingle(address(publicToken), address(0), 3000, 1e18, 0, _deadline());
    }

    function testSwapIdenticalTokensReverts() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticTreasury.IdenticalTokens.selector, address(publicToken)));
        treasury.swapExactInputSingle(address(publicToken), address(publicToken), 3000, 1e18, 0, _deadline());
    }

    function testSwapZeroAmountReverts() public {
        vm.expectRevert(AgenticTreasury.ZeroAmount.selector);
        treasury.swapExactInputSingle(address(publicToken), address(publicTokenB), 3000, 0, 0, _deadline());
    }

    function testSwapExpiredDeadlineReverts() public {
        uint256 deadline = block.timestamp - 1;

        vm.expectRevert(abi.encodeWithSelector(AgenticTreasury.DeadlineExpired.selector, deadline));
        treasury.swapExactInputSingle(address(publicToken), address(publicTokenB), 3000, 1e18, 0, deadline);
    }

    function testSwapDeadlineEqualToNowSucceeds() public {
        router.setAmountOut(1e18);
        uint256 deadline = block.timestamp;

        uint256 amountOut =
            treasury.swapExactInputSingle(address(publicToken), address(publicTokenB), 3000, 1e18, 0, deadline);
        assertEq(amountOut, 1e18);
    }

    function testSwapMinOutExceededReverts() public {
        router.setAmountOut(99);

        vm.expectRevert(abi.encodeWithSelector(AgenticTreasury.InsufficientOutput.selector, 99, 100));
        treasury.swapExactInputSingle(address(publicToken), address(publicTokenB), 3000, 1e18, 100, _deadline());
    }

    function testSwapMinOutEqualSucceeds() public {
        router.setAmountOut(100);

        uint256 amountOut =
            treasury.swapExactInputSingle(address(publicToken), address(publicTokenB), 3000, 1e18, 100, _deadline());
        assertEq(amountOut, 100);
    }

    function testSwapEmitsEvent() public {
        router.setAmountOut(321e18);

        vm.expectEmit(true, true, false, true, address(treasury));
        emit TreasurySwap(address(publicToken), address(publicTokenB), 100e18, 321e18);
        treasury.swapExactInputSingle(address(publicToken), address(publicTokenB), 3000, 100e18, 0, _deadline());
    }

    function testSwapRouterRevertPropagates() public {
        router.setRevertOnSwap(true);

        vm.expectRevert(MockSwapRouter.MockSwapReverted.selector);
        treasury.swapExactInputSingle(address(publicToken), address(publicTokenB), 3000, 1e18, 0, _deadline());
    }

    function testSwapOnlyGovernance() public {
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonGov));
        treasury.swapExactInputSingle(address(publicToken), address(publicTokenB), 3000, 1e18, 0, _deadline());
    }

    function testSwapUsesOnlyConfiguredRouter() public {
        MockSwapRouter otherRouter = new MockSwapRouter();
        router.setAmountOut(1e18);

        treasury.swapExactInputSingle(address(publicToken), address(publicTokenB), 3000, 1e18, 0, _deadline());

        assertEq(router.callCount(), 1);
        assertEq(otherRouter.callCount(), 0);
        assertEq(treasury.router(), address(router));
    }

    // -------------------------------------------------------------- no fallback

    function testNoArbitraryCallEntryPoint() public {
        (bool ok,) = address(treasury).call(abi.encodeWithSignature("execute(address,bytes)", nonAgent, ""));
        assertFalse(ok);

        (ok,) = address(treasury).call(abi.encodeWithSignature("delegatecall(address,bytes)", nonAgent, ""));
        assertFalse(ok);

        (ok,) = address(treasury).call(abi.encodeWithSignature("setRouter(address)", address(0x1234)));
        assertFalse(ok);
        assertEq(treasury.router(), address(router));

        (ok,) = address(treasury).call("");
        assertTrue(ok);
    }

    // ------------------------------------------------------------ distributeToken

    function testDistributeGatedToAgents() public {
        address[] memory recipients = new address[](2);
        recipients[0] = agent;
        recipients[1] = agent2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;
        amounts[1] = 2e18;

        treasury.distributeToken(address(gatedToken), recipients, amounts);

        assertEq(gatedToken.balanceOf(agent), 1e18);
        assertEq(gatedToken.balanceOf(agent2), 2e18);
        assertEq(gatedToken.balanceOf(address(treasury)), INITIAL_BALANCE - 3e18);
    }

    function testDistributeGatedToNonAgentReverts() public {
        address[] memory recipients = new address[](1);
        recipients[0] = nonAgent;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;

        vm.expectRevert(
            abi.encodeWithSelector(AgenticTreasury.GatedRecipientNotAgent.selector, address(gatedToken), nonAgent)
        );
        treasury.distributeToken(address(gatedToken), recipients, amounts);

        assertEq(gatedToken.balanceOf(address(treasury)), INITIAL_BALANCE);
    }

    function testDistributeGatedMixedRecipientsReverts() public {
        address[] memory recipients = new address[](2);
        recipients[0] = agent;
        recipients[1] = nonAgent;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;
        amounts[1] = 1e18;

        vm.expectRevert(
            abi.encodeWithSelector(AgenticTreasury.GatedRecipientNotAgent.selector, address(gatedToken), nonAgent)
        );
        treasury.distributeToken(address(gatedToken), recipients, amounts);

        assertEq(gatedToken.balanceOf(agent), 0);
        assertEq(gatedToken.balanceOf(address(treasury)), INITIAL_BALANCE);
    }

    function testDistributePublicToNonAgents() public {
        address[] memory recipients = new address[](2);
        recipients[0] = nonAgent;
        recipients[1] = nonGov;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;
        amounts[1] = 2e18;

        treasury.distributeToken(address(publicToken), recipients, amounts);

        assertEq(publicToken.balanceOf(nonAgent), 1e18);
        assertEq(publicToken.balanceOf(nonGov), 2e18);
    }

    function testDistributeOnlyGovernance() public {
        address[] memory recipients = new address[](1);
        recipients[0] = agent;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;

        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonGov));
        treasury.distributeToken(address(gatedToken), recipients, amounts);
    }

    function testDistributeLengthMismatchReverts() public {
        address[] memory recipients = new address[](2);
        recipients[0] = agent;
        recipients[1] = agent2;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;

        vm.expectRevert(abi.encodeWithSelector(AgenticTreasury.LengthMismatch.selector, 2, 1));
        treasury.distributeToken(address(gatedToken), recipients, amounts);
    }

    function testDistributeBatchTooLargeReverts() public {
        address[] memory recipients = new address[](MAX_BATCH + 1);
        uint256[] memory amounts = new uint256[](MAX_BATCH + 1);
        for (uint256 i; i < recipients.length; ++i) {
            recipients[i] = agent;
            amounts[i] = 1;
        }

        vm.expectRevert(abi.encodeWithSelector(AgenticTreasury.BatchTooLarge.selector, MAX_BATCH + 1, MAX_BATCH));
        treasury.distributeToken(address(gatedToken), recipients, amounts);
    }

    function testDistributeAtCapSucceeds() public {
        address[] memory recipients = new address[](MAX_BATCH);
        uint256[] memory amounts = new uint256[](MAX_BATCH);
        for (uint256 i; i < MAX_BATCH; ++i) {
            recipients[i] = agent;
            amounts[i] = 1e18;
        }

        treasury.distributeToken(address(gatedToken), recipients, amounts);

        assertEq(gatedToken.balanceOf(agent), MAX_BATCH * 1e18);
    }

    function testDistributeZeroTokenReverts() public {
        address[] memory recipients = new address[](1);
        recipients[0] = agent;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;

        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        treasury.distributeToken(address(0), recipients, amounts);
    }

    function testDistributeZeroRecipientReverts() public {
        address[] memory recipients = new address[](1);
        recipients[0] = address(0);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;

        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        treasury.distributeToken(address(gatedToken), recipients, amounts);
    }

    function testDistributeEmptyBatchAllowed() public {
        address[] memory recipients = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        treasury.distributeToken(address(gatedToken), recipients, amounts);
        assertEq(gatedToken.balanceOf(address(treasury)), INITIAL_BALANCE);
    }

    function testDistributeZeroAmountAllowed() public {
        address[] memory recipients = new address[](1);
        recipients[0] = agent;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;

        vm.expectEmit(true, true, false, true, address(treasury));
        emit TreasuryTransfer(address(gatedToken), agent, 0);
        treasury.distributeToken(address(gatedToken), recipients, amounts);

        assertEq(gatedToken.balanceOf(agent), 0);
    }

    function testDistributeInsufficientBalanceReverts() public {
        address[] memory recipients = new address[](1);
        recipients[0] = agent;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = INITIAL_BALANCE + 1;

        vm.expectRevert();
        treasury.distributeToken(address(gatedToken), recipients, amounts);
    }
}
