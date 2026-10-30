// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import {UniswapV3Factory} from "@uniswap/v3-core/contracts/UniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20Minimal} from "@uniswap/v3-core/contracts/interfaces/IERC20Minimal.sol";
import {TestERC20} from "@uniswap/v3-core/contracts/test/TestERC20.sol";

import {AgentswapPositionManager} from "../../contracts/AgentswapPositionManager.sol";
import {INonfungiblePositionManager} from "../../contracts/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "../../contracts/interfaces/ISwapRouter.sol";
import {AgentswapRouter} from "../../contracts/AgentswapRouter.sol";
import {AgentswapQuoter} from "../../contracts/lens/AgentswapQuoter.sol";
import {PoolAddress} from "../../contracts/libraries/PoolAddress.sol";

import {RealCoreFixture} from "../helpers/RealCoreFixture.sol";
import {TestBase} from "../helpers/TestBase.sol";
import {MockAssetRegistry} from "../mocks/MockAssetRegistry.sol";
import {MockPolicyToken} from "../mocks/MockPolicyToken.sol";
import {MockTransferPolicy} from "../mocks/MockTransferPolicy.sol";

/// @notice Integration tests for the unmodified 0.7.6 `AgentswapRouter` and `AgentswapQuoter`
/// against a real local V3 core pool created through the real factory.
/// @dev The router resolves pools through `PoolAddress.computeAddress` using
/// this deployment's `POOL_INIT_CODE_HASH`; the pool address assertions below
/// tie that constant to the factory-created pool used for every swap/quote.
contract RouterQuoterTest is RealCoreFixture {
    /// @dev Compact snapshot used to assert a quote call leaves no state behind
    /// without hitting solc 0.7.6 stack limits.
    struct Snapshot {
        uint160 sqrtPriceX96;
        int24 tick;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
        uint8 feeProtocol;
        bool unlocked;
        uint128 protocolFees0;
        uint128 protocolFees1;
        uint128 liquidity;
        uint256 pool0;
        uint256 pool1;
        uint256 quoter0;
        uint256 quoter1;
        uint256 router0;
        uint256 router1;
    }

    function setUp() public {
        _deployCore();
        _addLiquidity();
    }

    // ---------------------------------------------------------------------
    // Pool resolution
    // ---------------------------------------------------------------------

    function testPoolAddressMatchesFactoryAndLocalConstant() public {
        PoolAddress.PoolKey memory key = PoolAddress.PoolKey({token0: token0, token1: token1, fee: FEE});

        assertEq(PoolAddress.computeAddress(address(factory), key), address(pool));
        assertEq(factory.getPool(token0, token1, FEE), address(pool));
        // The router and quoter hold the same factory; their library-derived
        // address is the pool the swaps below actually hit.
        assertEq(PoolAddress.computeAddress(swapRouter.factory(), key), address(pool));
        assertEq(PoolAddress.computeAddress(quoter.factory(), key), address(pool));
    }

    // ---------------------------------------------------------------------
    // exactInputSingle, both directions
    // ---------------------------------------------------------------------

    function testExactInputSingleToken0ToToken1() public {
        (uint160 sqrtPriceBefore,,,,,,) = pool.slot0();
        uint256 payerBalanceBefore = IERC20Minimal(token0).balanceOf(address(this));
        uint256 recipientBalanceBefore = IERC20Minimal(token1).balanceOf(RECIPIENT);
        uint256 poolBalance0Before = IERC20Minimal(token0).balanceOf(address(pool));
        uint256 poolBalance1Before = IERC20Minimal(token1).balanceOf(address(pool));

        uint256 quoted = _quoteExactInputSingle(token0, token1, SWAP_AMOUNT);
        uint256 amountOut = _exactInputSingle(token0, token1, RECIPIENT, SWAP_AMOUNT, quoted, block.timestamp);

        assertTrue(quoted > 0);
        assertTrue(quoted < SWAP_AMOUNT);
        assertEq(amountOut, quoted);

        // The payer paid exactly amountIn and the recipient received exactly
        // amountOut; the router is only a pass-through and holds nothing.
        assertEq(IERC20Minimal(token0).balanceOf(address(this)), payerBalanceBefore - SWAP_AMOUNT);
        assertEq(IERC20Minimal(token1).balanceOf(RECIPIENT), recipientBalanceBefore + amountOut);
        assertEq(IERC20Minimal(token0).balanceOf(RECIPIENT), 0);
        assertEq(IERC20Minimal(token0).balanceOf(address(pool)), poolBalance0Before + SWAP_AMOUNT);
        assertEq(IERC20Minimal(token1).balanceOf(address(pool)), poolBalance1Before - amountOut);
        assertEq(IERC20Minimal(token0).balanceOf(address(swapRouter)), 0);
        assertEq(IERC20Minimal(token1).balanceOf(address(swapRouter)), 0);

        // token0 in => token0 price falls (sqrtPrice token1/token0 decreases).
        (uint160 sqrtPriceAfter,,,,,,) = pool.slot0();
        assertTrue(sqrtPriceAfter < sqrtPriceBefore);
    }

    function testExactInputSingleToken1ToToken0() public {
        (uint160 sqrtPriceBefore,,,,,,) = pool.slot0();
        uint256 payerBalanceBefore = IERC20Minimal(token1).balanceOf(address(this));
        uint256 recipientBalanceBefore = IERC20Minimal(token0).balanceOf(RECIPIENT);
        uint256 poolBalance0Before = IERC20Minimal(token0).balanceOf(address(pool));
        uint256 poolBalance1Before = IERC20Minimal(token1).balanceOf(address(pool));

        uint256 quoted = _quoteExactInputSingle(token1, token0, SWAP_AMOUNT);
        uint256 amountOut = _exactInputSingle(token1, token0, RECIPIENT, SWAP_AMOUNT, quoted, block.timestamp);

        assertTrue(quoted > 0);
        assertTrue(quoted < SWAP_AMOUNT);
        assertEq(amountOut, quoted);

        assertEq(IERC20Minimal(token1).balanceOf(address(this)), payerBalanceBefore - SWAP_AMOUNT);
        assertEq(IERC20Minimal(token0).balanceOf(RECIPIENT), recipientBalanceBefore + amountOut);
        assertEq(IERC20Minimal(token1).balanceOf(RECIPIENT), 0);
        assertEq(IERC20Minimal(token1).balanceOf(address(pool)), poolBalance1Before + SWAP_AMOUNT);
        assertEq(IERC20Minimal(token0).balanceOf(address(pool)), poolBalance0Before - amountOut);
        assertEq(IERC20Minimal(token0).balanceOf(address(swapRouter)), 0);
        assertEq(IERC20Minimal(token1).balanceOf(address(swapRouter)), 0);

        // token1 in => token1 price falls (sqrtPrice token1/token0 increases).
        (uint160 sqrtPriceAfter,,,,,,) = pool.slot0();
        assertTrue(sqrtPriceAfter > sqrtPriceBefore);
    }

    // ---------------------------------------------------------------------
    // AgentswapQuoter
    // ---------------------------------------------------------------------

    function testQuoterPositiveBothDirectionsAndStateFree() public {
        bytes32 stateBefore = _stateHash();

        uint256 amountOut0To1 = _quoteExactInputSingle(token0, token1, SWAP_AMOUNT);
        uint256 amountOut1To0 = _quoteExactInputSingle(token1, token0, SWAP_AMOUNT);

        assertTrue(amountOut0To1 > 0);
        assertTrue(amountOut1To0 > 0);
        assertTrue(amountOut0To1 < SWAP_AMOUNT);
        assertTrue(amountOut1To0 < SWAP_AMOUNT);

        // A quote must not move pool state, balances or protocol fees.
        assertTrue(_stateHash() == stateBefore);
    }

    function testQuoterMatchesSingleHopExecutionBothDirections() public {
        uint256 quoted0To1 = _quoteExactInputSingle(token0, token1, SWAP_AMOUNT);
        uint256 executed0To1 = _exactInputSingle(token0, token1, RECIPIENT, SWAP_AMOUNT, 0, block.timestamp);
        assertEq(executed0To1, quoted0To1);

        // Quote after the first swap uses the updated price, and still matches.
        uint256 quoted1To0 = _quoteExactInputSingle(token1, token0, SWAP_AMOUNT);
        uint256 executed1To0 = _exactInputSingle(token1, token0, RECIPIENT, SWAP_AMOUNT, 0, block.timestamp);
        assertEq(executed1To0, quoted1To0);

        assertTrue(quoted0To1 > 0);
        assertTrue(quoted1To0 > 0);
    }

    // ---------------------------------------------------------------------
    // Validation paths
    // ---------------------------------------------------------------------

    function testExpiredDeadlineRevertsAndLeavesStateUntouched() public {
        (uint160 sqrtPriceBefore,,,,,,) = pool.slot0();
        uint256 recipientBalanceBefore = IERC20Minimal(token1).balanceOf(RECIPIENT);

        vm.expectRevert(_errorString("Transaction too old"));
        _exactInputSingle(token0, token1, RECIPIENT, SWAP_AMOUNT, 0, 0);

        (uint160 sqrtPriceAfter,,,,,,) = pool.slot0();
        assertEq(sqrtPriceAfter, sqrtPriceBefore);
        assertEq(IERC20Minimal(token1).balanceOf(RECIPIENT), recipientBalanceBefore);
    }

    function testMinOutNotMetRevertsAndLeavesStateUntouched() public {
        uint256 quoted = _quoteExactInputSingle(token0, token1, SWAP_AMOUNT);
        uint256 recipientBalanceBefore = IERC20Minimal(token1).balanceOf(RECIPIENT);

        vm.expectRevert(_errorString("Too little received"));
        _exactInputSingle(token0, token1, RECIPIENT, SWAP_AMOUNT, quoted + 1, block.timestamp);

        assertEq(IERC20Minimal(token1).balanceOf(RECIPIENT), recipientBalanceBefore);
    }

    function testZeroAmountReverts() public {
        // Core requires a non-zero amountSpecified: the router does not add a
        // zero-amount shortcut that would let a caller grief or bypass a pool.
        vm.expectRevert(_errorString("AS"));
        _exactInputSingle(token0, token1, RECIPIENT, 0, 0, block.timestamp);
    }

    function testIdenticalTokensRevert() public {
        // PoolAddress.getPoolKey/computeAddress reject token0 == token1.
        vm.expectRevert();
        _exactInputSingle(token0, token0, RECIPIENT, SWAP_AMOUNT, 0, block.timestamp);

        vm.expectRevert();
        _quoteExactInputSingle(token0, token0, SWAP_AMOUNT);
    }

    function testUnapprovedPayerRevertsOnStandardERC20Allowance() public {
        address unapprovedPayer = address(0xCAFE);
        TestERC20(token0).mint(unapprovedPayer, SWAP_AMOUNT);

        // The router pulls with the standard TransferHelper path, so the ERC20
        // allowance check denies the swap ('STF' is the helper's wrapper).
        vm.prank(unapprovedPayer);
        vm.expectRevert(_errorString("STF"));
        _exactInputSingle(token0, token1, RECIPIENT, SWAP_AMOUNT, 0, block.timestamp);
    }

    // ---------------------------------------------------------------------
    // Gate boundary: no router-side agent/allowlist bypass
    // ---------------------------------------------------------------------

    /// @dev The router/quoter only implement the standard periphery ABI. They
    /// have no owner, admin, registry, policy, allowlist or pause surface, so
    /// they cannot grant an Agent-ID bypass. Token-level policy still governs
    /// transfers (the 0.8.20 cross-version proof is the gated fork).
    function testRouterAndQuoterExposeNoAdminOrAgentGate() public {
        _assertNoFunction(address(swapRouter), "owner()");
        _assertNoFunction(address(swapRouter), "admin()");
        _assertNoFunction(address(swapRouter), "governance()");
        _assertNoFunction(address(swapRouter), "setAgentRegistry(address)");
        _assertNoFunction(address(swapRouter), "setAssetRegistry(address)");
        _assertNoFunction(address(swapRouter), "setPolicy(address)");
        _assertNoFunction(address(swapRouter), "setAllowlist(address,bool)");
        _assertNoFunction(address(swapRouter), "setTreasury(address)");
        _assertNoFunction(address(swapRouter), "setRouter(address)");
        _assertNoFunction(address(swapRouter), "setFactory(address)");
        _assertNoFunction(address(swapRouter), "pause()");
        _assertNoFunction(address(swapRouter), "unpause()");

        _assertNoFunction(address(quoter), "owner()");
        _assertNoFunction(address(quoter), "admin()");
        _assertNoFunction(address(quoter), "setAgentRegistry(address)");
        _assertNoFunction(address(quoter), "setAssetRegistry(address)");
        _assertNoFunction(address(quoter), "setPolicy(address)");
        _assertNoFunction(address(quoter), "setAllowlist(address,bool)");
        _assertNoFunction(address(quoter), "setFactory(address)");
        _assertNoFunction(address(quoter), "pause()");

        // Only the immutable deployment references are exposed.
        (bool routerFactoryOk, bytes memory routerFactoryData) =
            address(swapRouter).staticcall(abi.encodeWithSignature("factory()"));
        assertTrue(routerFactoryOk);
        assertEq(abi.decode(routerFactoryData, (address)), address(factory));

        (bool routerWeth9Ok, bytes memory routerWeth9Data) =
            address(swapRouter).staticcall(abi.encodeWithSignature("WETH9()"));
        assertTrue(routerWeth9Ok);
        assertEq(abi.decode(routerWeth9Data, (address)), WETH9);

        (bool quoterFactoryOk, bytes memory quoterFactoryData) =
            address(quoter).staticcall(abi.encodeWithSignature("factory()"));
        assertTrue(quoterFactoryOk);
        assertEq(abi.decode(quoterFactoryData, (address)), address(factory));
    }

    function _stateHash() private view returns (bytes32) {
        Snapshot memory snapshot;
        (
            snapshot.sqrtPriceX96,
            snapshot.tick,
            snapshot.observationIndex,
            snapshot.observationCardinality,
            snapshot.observationCardinalityNext,
            snapshot.feeProtocol,
            snapshot.unlocked
        ) = pool.slot0();
        (snapshot.protocolFees0, snapshot.protocolFees1) = pool.protocolFees();
        snapshot.liquidity = pool.liquidity();
        snapshot.pool0 = IERC20Minimal(token0).balanceOf(address(pool));
        snapshot.pool1 = IERC20Minimal(token1).balanceOf(address(pool));
        snapshot.quoter0 = IERC20Minimal(token0).balanceOf(address(quoter));
        snapshot.quoter1 = IERC20Minimal(token1).balanceOf(address(quoter));
        snapshot.router0 = IERC20Minimal(token0).balanceOf(address(swapRouter));
        snapshot.router1 = IERC20Minimal(token1).balanceOf(address(swapRouter));
        return keccak256(abi.encode(snapshot));
    }

    function _assertNoFunction(address target, string memory signature) private {
        (bool ok,) = target.call(abi.encodeWithSignature(signature));
        assertFalse(ok);
    }

    function _errorString(string memory message) private pure returns (bytes memory) {
        return abi.encodeWithSignature("Error(string)", message);
    }
}

/// @notice Proves the gate boundary at the router/quoter layer with a policy
/// aware token: the router is policy-neutral and performs standard ERC20
/// transfers, so the token's own policy decides who may pay/receive. There is
/// no router-side agent check or allowlist that could be bypassed.
/// @dev 0.7.6 mock stand-in for the 0.8.20 AgenticToken; the real cross-version
/// token/policy path is the gated fork. The NPM registry is empty, so the the NPM NPM gate
/// does not interfere: every denial below comes from the token policy.
contract RouterPolicyBoundaryTest is TestBase {
    uint24 private constant FEE = 3000;
    int24 private constant MIN_TICK = -887220;
    int24 private constant MAX_TICK = 887220;
    uint160 private constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    uint256 private constant LP_AMOUNT = 1e21;
    uint256 private constant SWAP_AMOUNT = 1e18;

    uint8 private constant CATEGORY_POOL = 1;

    address private constant WETH9 = address(0xBEEF);
    address private constant AGENT = address(0xA11CE);
    address private constant NON_AGENT = address(0xBAD);

    UniswapV3Factory private factory;
    IUniswapV3Pool private pool;
    address private poolAddress;
    MockTransferPolicy private policy;
    MockPolicyToken private gatedToken;
    TestERC20 private quoteToken;
    AgentswapPositionManager private npm;
    AgentswapRouter private router;
    AgentswapQuoter private quoter;

    function setUp() public {
        factory = new UniswapV3Factory();
        policy = new MockTransferPolicy();
        gatedToken = new MockPolicyToken(address(policy), 1e30);
        quoteToken = new TestERC20(1e30);

        (address token0, address token1) = _sort(address(gatedToken), address(quoteToken));
        pool = IUniswapV3Pool(factory.createPool(token0, token1, FEE));
        pool.initialize(SQRT_PRICE_1_1);
        poolAddress = address(pool);

        // The test contract and AGENT are agents (member, category NONE); the
        // pool is a POOL facility, exactly what the router path needs.
        policy.setMember(address(this), true);
        policy.setMember(AGENT, true);
        policy.setCategory(poolAddress, CATEGORY_POOL);

        MockAssetRegistry registry = new MockAssetRegistry();
        npm = AgentswapPositionManager(
            payable(vm.deployCode(
                    "AgentswapPositionManager.sol:AgentswapPositionManager",
                    abi.encode(address(factory), WETH9, address(0), address(registry))
                ))
        );
        router = AgentswapRouter(
            payable(vm.deployCode("AgentswapRouter.sol:AgentswapRouter", abi.encode(address(factory), WETH9)))
        );
        quoter =
            AgentswapQuoter(vm.deployCode("AgentswapQuoter.sol:AgentswapQuoter", abi.encode(address(factory), WETH9)));

        gatedToken.approve(address(npm), uint256(-1));
        quoteToken.approve(address(npm), uint256(-1));
        gatedToken.approve(address(router), uint256(-1));
        quoteToken.approve(address(router), uint256(-1));

        npm.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: FEE,
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                amount0Desired: LP_AMOUNT,
                amount1Desired: LP_AMOUNT,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: uint256(-1)
            })
        );
    }

    function testAgentReceivesGatedTokenThroughRouter() public {
        uint256 amountOut = _swap(address(quoteToken), address(gatedToken), AGENT, SWAP_AMOUNT);

        assertTrue(amountOut > 0);
        assertEq(gatedToken.balanceOf(AGENT), amountOut);
    }

    function testNonAgentRecipientDeniedByTokenPolicy() public {
        // The pool -> recipient leg is a plain ERC20 transfer; the token policy
        // rejects the non-agent recipient and the core wraps that as 'TF'.
        vm.expectRevert(_errorString("TF"));
        _swap(address(quoteToken), address(gatedToken), NON_AGENT, SWAP_AMOUNT);

        assertEq(gatedToken.balanceOf(NON_AGENT), 0);
    }

    function testNonAgentPayerDeniedByTokenPolicy() public {
        // Fund and approve as the non-agent, but the router's standard
        // transferFrom is rejected by the token policy ('STF' from the router
        // payment helper), so the router cannot act as an identity bypass.
        gatedToken.mint(NON_AGENT, SWAP_AMOUNT);
        vm.prank(NON_AGENT);
        gatedToken.approve(address(router), SWAP_AMOUNT);

        vm.prank(NON_AGENT);
        vm.expectRevert(_errorString("STF"));
        _swap(address(gatedToken), address(quoteToken), AGENT, SWAP_AMOUNT);

        assertEq(quoteToken.balanceOf(AGENT), 0);
    }

    function testQuoterIsUngatedAndMatchesAgentExecution() public {
        // A quote never transfers tokens: it simulates the swap and reverts in
        // the callback, so it returns a positive amount without consulting (or
        // bypassing) policy. Execution is still token-policy gated.
        uint256 quoted = quoter.quoteExactInputSingle(address(gatedToken), address(quoteToken), FEE, SWAP_AMOUNT, 0);
        assertTrue(quoted > 0);

        uint256 executed = _swap(address(gatedToken), address(quoteToken), AGENT, SWAP_AMOUNT);
        assertEq(executed, quoted);
        assertEq(quoteToken.balanceOf(AGENT), quoted);
    }

    function testTokenPolicyItselfDeniesPoolToNonAgent() public {
        // Direct evidence that the denial lives in the token, independent of
        // the router: the pool may pay an agent but not a non-agent.
        vm.prank(poolAddress);
        vm.expectRevert(_errorString("policy: denied"));
        gatedToken.transfer(NON_AGENT, 1);

        uint256 agentBalanceBefore = gatedToken.balanceOf(AGENT);
        vm.prank(poolAddress);
        gatedToken.transfer(AGENT, 1);
        assertEq(gatedToken.balanceOf(AGENT), agentBalanceBefore + 1);
    }

    function _swap(address tokenIn, address tokenOut, address recipient, uint256 amountIn)
        private
        returns (uint256 amountOut)
    {
        amountOut = router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: FEE,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function _sort(address a, address b) private pure returns (address a0, address a1) {
        if (a < b) return (a, b);
        return (b, a);
    }

    function _errorString(string memory message) private pure returns (bytes memory) {
        return abi.encodeWithSignature("Error(string)", message);
    }
}
