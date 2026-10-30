// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {FacilityCategory, NPM, POOL} from "../../contracts/common/Types.sol";
import {AgentswapPoolFactory} from "../../contracts/pool/AgentswapPoolFactory.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";
import {AgenticTreasury} from "../../contracts/treasury/AgenticTreasury.sol";

import {DexArtifactDeployer} from "../helpers/DexArtifactDeployer.sol";
import {MockPositionDescriptor} from "../helpers/MockPositionDescriptor.sol";
import {MockWETH9} from "../helpers/MockWETH9.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {IntegrationFixture} from "./IntegrationFixture.sol";

// ---------------------------------------------------------------------------
// Minimal 0.8.20 ABI mirrors of the 0.7.6 dex contracts.
//
// These are local test interfaces only: no 0.7.6 import, no struct is shared
// with the dex project. The periphery structs below are encoded as ABI tuples
// across the version boundary, exactly like any other external caller.
// ---------------------------------------------------------------------------

interface ICrossVersionV3Factory {
    function owner() external view returns (address);
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
    function setOwner(address newOwner) external;
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external;
}

interface ICrossVersionV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
    function initialize(uint160 sqrtPriceX96) external;
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
    function liquidity() external view returns (uint128);
    function protocolFees() external view returns (uint128 token0, uint128 token1);
    function positions(bytes32 key)
        external
        view
        returns (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
    function mint(address recipient, int24 tickLower, int24 tickUpper, uint128 amount, bytes calldata data)
        external
        returns (uint256 amount0, uint256 amount1);
    function burn(int24 tickLower, int24 tickUpper, uint128 amount) external returns (uint256 amount0, uint256 amount1);
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);
}

interface ICrossVersionNpm {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
    function policyOfToken(address token) external view returns (address);
    function isAllowedRecipient(address token, address to) external view returns (bool);
    function isAllowedTransfer(uint256 tokenId, address from, address to) external view returns (bool);
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function factory() external view returns (address);
    function WETH9() external view returns (address);
    function ownerOf(uint256 tokenId) external view returns (address);
    function balanceOf(address owner_) external view returns (uint256);
    function approve(address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
}

interface ICrossVersionSwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
    function factory() external view returns (address);
    function WETH9() external view returns (address);
}

interface ICrossVersionQuoter {
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
    function factory() external view returns (address);
}

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

/// @notice Cross-version fixture: the real protocol 0.8.20 stack from
/// `IntegrationFixture`, plus the separately built 0.7.6 core/periphery
/// (NPM fork and cross-version gated-aware AgentswapQuoter fork).
/// @dev Build order: `cd dex && forge build` (or `make dex-build`) before
/// `forge test`. The root test reads only `dex/out` artifacts through
/// `vm.getCode`/`vm.deployCode`; the DEX/protocol sources are not linked or edited.
abstract contract CrossVersionDexFixture is IntegrationFixture {
    uint24 internal constant FEE = 3000;
    int24 internal constant MIN_TICK = -887220;
    int24 internal constant MAX_TICK = 887220;
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336; // 2^96

    uint256 internal constant GATED_SUPPLY = 1_000_000 ether;
    uint256 internal constant QUOTE_SUPPLY = 1_000_000 ether;
    uint256 internal constant LP_AMOUNT = 1_000 ether;
    uint256 internal constant SWAP_AMOUNT = 1 ether;
    uint128 internal constant RAW_LIQUIDITY = 100 ether;

    bytes4 internal constant ERR_NOT_AGENT = bytes4(keccak256("NotAgent()"));
    bytes4 internal constant ERR_OWNER_CALLER = bytes4(keccak256("NotAgentOwnerOrCaller()"));
    bytes4 internal constant ERR_TRANSFER = bytes4(keccak256("NotAgentTransfer()"));

    ICrossVersionV3Factory internal v3Factory;
    ICrossVersionV3Pool internal v3Pool;
    address internal poolAddress;
    AgentswapPoolFactory internal gatedFactory;
    ICrossVersionNpm internal npm;
    ICrossVersionSwapRouter internal swapRouter;
    ICrossVersionQuoter internal quoter;
    MockWETH9 internal weth9;
    MockPositionDescriptor internal descriptor;
    AgenticToken internal gated;
    MockToken internal quote;

    address internal token0;
    address internal token1;
    bool internal gatedIsToken0;

    function setUp() public virtual override {
        super.setUp();
        DexArtifactDeployer.requireArtifacts();

        _deployCoreAndAssets();
        _deployGatedFactory();
        _deployPeriphery();
        _createGatedPool();
        _approveAgent();
    }

    // ------------------------------------------------------------------
    // Deployment
    // ------------------------------------------------------------------

    /// @dev 0.7.6 V3 factory (no args) plus the root gated token/public quote
    /// and the root mock periphery dependencies. The fourth fee tier is enabled
    /// while the test contract still owns the canonical factory; ownership is
    /// handed to the root wrapper in `_deployGatedFactory`.
    function _deployCoreAndAssets() private {
        v3Factory = ICrossVersionV3Factory(DexArtifactDeployer.deployFactory());
        v3Factory.enableFeeAmount(100, 1);

        gated = _createTokenFor(agent, GATED_SUPPLY);
        quote = new MockToken();
        quote.mint(agent, QUOTE_SUPPLY);
        quoteRegistry.addQuoteAsset(address(quote));

        weth9 = new MockWETH9();
        descriptor = new MockPositionDescriptor();
    }

    /// @dev Root 0.8.20 `AgentswapPoolFactory` over the 0.7.6 canonical factory.
    function _deployGatedFactory() private {
        gatedFactory = new AgentswapPoolFactory(
            address(v3Factory),
            address(assetRegistry),
            address(quoteRegistry),
            address(venue),
            address(policyRegistry),
            address(treasury),
            address(this)
        );

        v3Factory.setOwner(address(gatedFactory));
        venue.setRegistrar(address(gatedFactory), FacilityCategory.POOL, true);
    }

    /// @dev 0.7.6 periphery with the NPM fork and the cross-version gated AgentswapQuoter
    /// fork. The NPM receives the real root asset registry, and the mock
    /// WETH9/descriptor have code (no mainnet addresses, no codeless
    /// placeholders).
    function _deployPeriphery() private {
        npm = ICrossVersionNpm(
            DexArtifactDeployer.deployNonfungiblePositionManager(
                address(v3Factory), address(weth9), address(descriptor), address(assetRegistry)
            )
        );
        swapRouter = ICrossVersionSwapRouter(DexArtifactDeployer.deploySwapRouter(address(v3Factory), address(weth9)));
        quoter = ICrossVersionQuoter(DexArtifactDeployer.deployQuoter(address(v3Factory), address(weth9)));

        venue.registerFacility(address(npm), NPM);
    }

    /// @dev Gated token + public quote pool at exactly 1:1 through the wrapper.
    /// The project owner created the token (no Agent ID needed), so it is the
    /// only authorized pool creator.
    function _createGatedPool() private {
        vm.prank(projectOwner);
        poolAddress = gatedFactory.createPool(address(gated), address(quote), FEE, SQRT_PRICE_1_1);
        v3Pool = ICrossVersionV3Pool(poolAddress);

        (token0, token1) =
            address(gated) < address(quote) ? (address(gated), address(quote)) : (address(quote), address(gated));
        gatedIsToken0 = token0 == address(gated);
    }

    /// @dev Agent approvals for the periphery and for the raw-mint callback.
    function _approveAgent() private {
        vm.startPrank(agent);
        gated.approve(address(npm), type(uint256).max);
        quote.approve(address(npm), type(uint256).max);
        gated.approve(address(swapRouter), type(uint256).max);
        quote.approve(address(swapRouter), type(uint256).max);
        gated.approve(address(this), type(uint256).max);
        quote.approve(address(this), type(uint256).max);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _mintParams(address recipient) internal view returns (ICrossVersionNpm.MintParams memory) {
        return ICrossVersionNpm.MintParams({
            token0: token0,
            token1: token1,
            fee: FEE,
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            amount0Desired: LP_AMOUNT,
            amount1Desired: LP_AMOUNT,
            amount0Min: 0,
            amount1Min: 0,
            recipient: recipient,
            deadline: block.timestamp
        });
    }

    function _mintLp(address caller, address recipient)
        internal
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        vm.prank(caller);
        (tokenId, liquidity, amount0, amount1) = npm.mint(_mintParams(recipient));
    }

    function _swapParams(address tokenIn, address tokenOut, address recipient, uint256 amountIn)
        internal
        view
        returns (ICrossVersionSwapRouter.ExactInputSingleParams memory)
    {
        return ICrossVersionSwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: FEE,
            recipient: recipient,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
    }

    function _exactInputSingle(address tokenIn, address tokenOut, address recipient, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        amountOut = swapRouter.exactInputSingle(_swapParams(tokenIn, tokenOut, recipient, amountIn));
    }

    function _swapAs(address caller, address tokenIn, address tokenOut, address recipient, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        vm.prank(caller);
        amountOut = _exactInputSingle(tokenIn, tokenOut, recipient, amountIn);
    }

    function _quote(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amountOut) {
        amountOut = quoter.quoteExactInputSingle(tokenIn, tokenOut, FEE, amountIn, 0);
    }

    /// @dev The cross-version AgentswapQuoter simulates the payout to `msg.sender`; use an agent
    /// caller for gated-output quotes (a non-agent caller is policy-denied).
    function _quoteAs(address caller, address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        vm.prank(caller);
        amountOut = _quote(tokenIn, tokenOut, amountIn);
    }

    function _positionKey(address owner_) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner_, MIN_TICK, MAX_TICK));
    }

    function _poolPosition(address owner_)
        internal
        view
        returns (uint128 liquidity, uint128 tokensOwed0, uint128 tokensOwed1)
    {
        (liquidity,,, tokensOwed0, tokensOwed1) = v3Pool.positions(_positionKey(owner_));
    }

    function _errorString(string memory message) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("Error(string)", message);
    }

    function _assertNoFunction(address target, string memory signature) internal {
        (bool ok,) = target.call(abi.encodeWithSignature(signature));
        assertFalse(ok);
    }

    /// @dev 0.7.6 core mint callback used only by the raw-position residual
    /// test: `data` is the payer address, funded through an ERC-20 allowance.
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external {
        require(msg.sender == poolAddress, "cross-version: callback caller is not the pool");
        address payer = abi.decode(data, (address));

        if (amount0Owed > 0) IERC20(token0).transferFrom(payer, poolAddress, amount0Owed);
        if (amount1Owed > 0) IERC20(token1).transferFrom(payer, poolAddress, amount1Owed);
    }
}

// ---------------------------------------------------------------------------
// Main cross-version path
// ---------------------------------------------------------------------------

/// @notice A real 0.8.20 protocol token/policy/registry/treasury stack driving
/// the separately built 0.7.6 V3 core, NPM fork, AgentswapRouter and gated-aware
/// AgentswapQuoter fork.
contract CrossVersionDexTest is CrossVersionDexFixture {
    // ------------------------------------------------------------------
    // Pool creation / registries
    // ------------------------------------------------------------------

    function testPoolCreatedAtOneToOneAndRegistered() public view {
        assertEq(v3Factory.getPool(address(gated), address(quote), FEE), poolAddress);
        assertEq(v3Pool.token0(), token0);
        assertEq(v3Pool.token1(), token1);
        assertEq(uint256(v3Pool.fee()), uint256(FEE));

        (uint160 sqrtPriceX96, int24 tick,,,, uint8 feeProtocol, bool unlocked) = v3Pool.slot0();
        assertEq(uint256(sqrtPriceX96), uint256(SQRT_PRICE_1_1));
        assertEq(int256(tick), int256(0));
        // V3 packs the two sides as feeProtocol0 | (feeProtocol1 << 4), so the
        // wrapper's (8,8) is returned as 0x88 by slot0(), not as 8.
        assertEq(uint256(feeProtocol), 136);
        assertEq(uint256(feeProtocol & 0x0f), 8);
        assertEq(uint256(feeProtocol >> 4), 8);
        assertTrue(unlocked);

        (uint128 protocolFees0, uint128 protocolFees1) = v3Pool.protocolFees();
        assertEq(uint256(protocolFees0), 0);
        assertEq(uint256(protocolFees1), 0);

        // The wrapper owns the canonical factory and is its POOL registrar.
        assertEq(v3Factory.owner(), address(gatedFactory));
        assertTrue(venue.isFacilityOfCategory(poolAddress, FacilityCategory.POOL));
        assertEq(venue.facilityType(poolAddress), POOL);
        assertEq(venue.factoryOf(poolAddress), address(gatedFactory));

        // Asset registry: gated asset recorded, public quote not recorded.
        assertTrue(assetRegistry.isRegistered(address(gated)));
        assertEq(assetRegistry.policyOf(address(gated)), address(policy));
        address[] memory pools = assetRegistry.poolsOf(address(gated));
        assertEq(pools.length, 1);
        assertEq(pools[0], poolAddress);
        assertEq(assetRegistry.poolsOf(address(quote)).length, 0);
        assertFalse(assetRegistry.isRegistered(address(quote)));

        // The real 0.7.6 NPM is registered as an LP_MANAGER venue facility.
        assertTrue(venue.isFacilityOfType(address(npm), NPM));
        assertEq(uint256(venue.facilityCategory(address(npm))), uint256(FacilityCategory.LP_MANAGER));

        // Real treasury is the active fee recipient and the wrapper's target.
        assertEq(gatedFactory.treasury(), address(treasury));
        assertTrue(venue.isFacilityOfCategory(address(treasury), FacilityCategory.FEE_RECIPIENT));

        // All four canonical fee tiers (100 enabled before ownership transfer).
        assertEq(int256(v3Factory.feeAmountTickSpacing(100)), int256(1));
        assertEq(int256(v3Factory.feeAmountTickSpacing(500)), int256(10));
        assertEq(int256(v3Factory.feeAmountTickSpacing(3000)), int256(60));
        assertEq(int256(v3Factory.feeAmountTickSpacing(10000)), int256(200));
        assertTrue(gatedFactory.isAllowedFee(100));
        assertTrue(gatedFactory.isAllowedFee(500));
        assertTrue(gatedFactory.isAllowedFee(3000));
        assertTrue(gatedFactory.isAllowedFee(10000));
    }

    // ------------------------------------------------------------------
    // NPM LP by agent
    // ------------------------------------------------------------------

    function testNpmAgentMintsFullRangePosition() public {
        uint256 agentGatedBefore = gated.balanceOf(agent);
        uint256 agentQuoteBefore = quote.balanceOf(agent);

        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = _mintLp(agent, agent);

        assertGt(uint256(liquidity), 0);
        assertGt(amount0, 0);
        assertGt(amount1, 0);
        assertEq(npm.ownerOf(tokenId), agent);
        assertEq(npm.balanceOf(agent), 1);
        assertEq(uint256(v3Pool.liquidity()), uint256(liquidity));

        uint256 gatedUsed = gatedIsToken0 ? amount0 : amount1;
        uint256 quoteUsed = gatedIsToken0 ? amount1 : amount0;
        assertEq(agentGatedBefore - gated.balanceOf(agent), gatedUsed);
        assertEq(agentQuoteBefore - quote.balanceOf(agent), quoteUsed);
        assertEq(gated.balanceOf(poolAddress), gatedUsed);
        assertEq(quote.balanceOf(poolAddress), quoteUsed);

        // Live 0.7.6 NPM -> 0.8.20 AgenticAssetRegistry/policy reads.
        assertEq(npm.policyOfToken(address(gated)), address(policy));
        assertEq(npm.policyOfToken(address(quote)), address(0));
        assertTrue(npm.isAllowedRecipient(address(gated), agent));
        assertFalse(npm.isAllowedRecipient(address(gated), nonAgent));
        assertTrue(npm.isAllowedRecipient(address(quote), nonAgent));
        assertTrue(npm.isAllowedTransfer(tokenId, agent, agent));
        assertFalse(npm.isAllowedTransfer(tokenId, agent, nonAgent));

        // 0.7.6 NPM -> 0.8.20 descriptor call.
        assertEq(npm.tokenURI(tokenId), "mock://dex-position");

        _assertPosition(tokenId, liquidity);
    }

    function testNpmRejectsNonAgentRecipient() public {
        vm.prank(agent);
        vm.expectRevert(ERR_NOT_AGENT);
        npm.mint(_mintParams(nonAgent));
    }

    function testNpmRejectsNonAgentCaller() public {
        // Recipient is the agent, so only the caller check can deny this mint.
        vm.prank(nonAgent);
        vm.expectRevert(ERR_NOT_AGENT);
        npm.mint(_mintParams(agent));
    }

    // ------------------------------------------------------------------
    // Router / quoter
    // ------------------------------------------------------------------

    function testRouterGatedToQuoteQuoteMatchesExecution() public {
        _mintLp(agent, agent);

        uint256 poolGatedBefore = gated.balanceOf(poolAddress);
        uint256 poolQuoteBefore = quote.balanceOf(poolAddress);
        (uint160 sqrtBefore,,,,,,) = v3Pool.slot0();
        (uint128 protocolFees0Before, uint128 protocolFees1Before) = v3Pool.protocolFees();

        // Gated input / public output: the quote is caller-agnostic.
        uint256 quoted = _quoteAs(agent, address(gated), address(quote), SWAP_AMOUNT);
        assertGt(quoted, 0);
        assertLt(quoted, SWAP_AMOUNT);

        // A quote must not move pool state, balances or protocol fees.
        {
            (uint160 sqrtAfterQuote,,,,,,) = v3Pool.slot0();
            assertEq(uint256(sqrtAfterQuote), uint256(sqrtBefore));
            (uint128 protocolFees0After, uint128 protocolFees1After) = v3Pool.protocolFees();
            assertEq(uint256(protocolFees0After), uint256(protocolFees0Before));
            assertEq(uint256(protocolFees1After), uint256(protocolFees1Before));
            assertEq(gated.balanceOf(address(quoter)), 0);
            assertEq(quote.balanceOf(address(quoter)), 0);
        }

        uint256 agent2QuoteBefore = quote.balanceOf(agent2);
        uint256 executed = _swapAs(agent, address(gated), address(quote), agent2, SWAP_AMOUNT);
        assertEq(executed, quoted);
        assertEq(quote.balanceOf(agent2), agent2QuoteBefore + executed);
        assertEq(gated.balanceOf(poolAddress), poolGatedBefore + SWAP_AMOUNT);
        assertEq(quote.balanceOf(poolAddress), poolQuoteBefore - executed);

        {
            (uint160 sqrtAfterSwap,,,,,,) = v3Pool.slot0();
            if (gatedIsToken0) {
                assertLt(uint256(sqrtAfterSwap), uint256(sqrtBefore));
            } else {
                assertGt(uint256(sqrtAfterSwap), uint256(sqrtBefore));
            }
        }

        // The router is a pure pass-through.
        assertEq(gated.balanceOf(address(swapRouter)), 0);
        assertEq(quote.balanceOf(address(swapRouter)), 0);
    }

    function testRouterQuoteToGatedQuoteMatchesExecution() public {
        _mintLp(agent, agent);

        uint256 poolGatedBefore = gated.balanceOf(poolAddress);
        uint256 poolQuoteBefore = quote.balanceOf(poolAddress);
        uint256 agentGatedBefore = gated.balanceOf(agent);
        (uint160 sqrtBefore,,,,,,) = v3Pool.slot0();

        // The cross-version AgentswapQuoter simulates the gated payout to the agent caller, so
        // this gated-output quote is policy-allowed and matches execution.
        uint256 quoted = _quoteAs(agent, address(quote), address(gated), SWAP_AMOUNT);
        assertGt(quoted, 0);
        assertLt(quoted, SWAP_AMOUNT);
        assertEq(gated.balanceOf(agent), agentGatedBefore);
        {
            (uint160 sqrtAfterQuote,,,,,,) = v3Pool.slot0();
            assertEq(uint256(sqrtAfterQuote), uint256(sqrtBefore));
        }

        uint256 agent2GatedBefore = gated.balanceOf(agent2);
        uint256 executed = _swapAs(agent, address(quote), address(gated), agent2, SWAP_AMOUNT);
        assertEq(executed, quoted);
        assertEq(gated.balanceOf(agent2), agent2GatedBefore + executed);
        assertEq(quote.balanceOf(poolAddress), poolQuoteBefore + SWAP_AMOUNT);
        assertEq(gated.balanceOf(poolAddress), poolGatedBefore - executed);

        {
            (uint160 sqrtAfterSwap,,,,,,) = v3Pool.slot0();
            if (gatedIsToken0) {
                assertGt(uint256(sqrtAfterSwap), uint256(sqrtBefore));
            } else {
                assertLt(uint256(sqrtAfterSwap), uint256(sqrtBefore));
            }
        }

        // The router is a pure pass-through.
        assertEq(gated.balanceOf(address(swapRouter)), 0);
        assertEq(quote.balanceOf(address(swapRouter)), 0);
    }

    function testRouterRejectsGatedOutputToNpm() public {
        _mintLp(agent, agent);

        // POOL -> LP_MANAGER is no longer a policy exception, so a swap cannot
        // park gated output at the NPM (and the permissionless sweep route is
        // closed for gated tokens).
        vm.prank(agent);
        vm.expectRevert(_errorString("TF"));
        _exactInputSingle(address(quote), address(gated), address(npm), SWAP_AMOUNT);
    }

    function testRouterRejectsGatedOutputToNonAgent() public {
        _mintLp(agent, agent);

        (uint160 sqrtBefore,,,,,,) = v3Pool.slot0();
        uint256 poolGatedBefore = gated.balanceOf(poolAddress);
        uint256 poolQuoteBefore = quote.balanceOf(poolAddress);
        uint256 agentQuoteBefore = quote.balanceOf(agent);
        uint256 nonAgentGatedBefore = gated.balanceOf(nonAgent);

        // quote -> gated: the pool -> recipient leg is the token's policy call.
        vm.prank(agent);
        vm.expectRevert(_errorString("TF"));
        _exactInputSingle(address(quote), address(gated), nonAgent, SWAP_AMOUNT);

        (uint160 sqrtAfter,,,,,,) = v3Pool.slot0();
        assertEq(uint256(sqrtAfter), uint256(sqrtBefore));
        assertEq(gated.balanceOf(poolAddress), poolGatedBefore);
        assertEq(quote.balanceOf(poolAddress), poolQuoteBefore);
        assertEq(quote.balanceOf(agent), agentQuoteBefore);
        assertEq(gated.balanceOf(nonAgent), nonAgentGatedBefore);
    }

    function testGatedInputFromNonAgentImpossible() public {
        _mintLp(agent, agent);

        // The policy denies agent -> non-agent, so a non-agent cannot acquire
        // the gated token that would be needed to pay a gated input.
        assertEq(gated.balanceOf(nonAgent), 0);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticToken.TransferDenied.selector, keccak256("NOT_ELIGIBLE")));
        gated.transfer(nonAgent, 1);

        // A non-agent calling the router cannot make the router pull an agent's
        // balance: exactInputSingle always pays from msg.sender.
        vm.prank(nonAgent);
        vm.expectRevert();
        _exactInputSingle(address(gated), address(quote), nonAgent, SWAP_AMOUNT);
        assertEq(gated.balanceOf(nonAgent), 0);
    }

    // ------------------------------------------------------------------
    // Protocol fee / treasury
    // ------------------------------------------------------------------

    function testProtocolFeeCollectedToTreasuryAndGatedFeeToAgent() public {
        _mintLp(agent, agent);

        _swapAs(agent, address(gated), address(quote), agent2, SWAP_AMOUNT);
        _swapAs(agent, address(quote), address(gated), agent2, SWAP_AMOUNT);

        (uint128 protocolFees0, uint128 protocolFees1) = v3Pool.protocolFees();
        assertGt(uint256(protocolFees0), 0);
        assertGt(uint256(protocolFees1), 0);

        uint256 treasuryGatedBefore = gated.balanceOf(address(treasury));
        uint256 treasuryQuoteBefore = quote.balanceOf(address(treasury));

        (uint128 collected0, uint128 collected1) =
            gatedFactory.collectProtocol(poolAddress, type(uint128).max, type(uint128).max);

        // Uniswap V3 deliberately leaves 1 wei in each non-zero protocol-fee
        // slot (`collectProtocol` decrements a full-balance collection to avoid
        // clearing the storage slot), so the returned amount is one wei below
        // protocolFees() when collecting the whole balance.
        assertEq(uint256(collected0) + 1, uint256(protocolFees0));
        assertEq(uint256(collected1) + 1, uint256(protocolFees1));

        uint256 gatedFee = gatedIsToken0 ? collected0 : collected1;
        uint256 quoteFee = gatedIsToken0 ? collected1 : collected0;
        assertGt(gatedFee, 0);
        assertGt(quoteFee, 0);
        assertEq(gated.balanceOf(address(treasury)), treasuryGatedBefore + gatedFee);
        assertEq(quote.balanceOf(address(treasury)), treasuryQuoteBefore + quoteFee);

        (uint128 protocolFees0After, uint128 protocolFees1After) = v3Pool.protocolFees();
        assertEq(uint256(protocolFees0After), 1);
        assertEq(uint256(protocolFees1After), 1);

        // Gated protocol fee held by the treasury is a stopover: it may leave
        // only to an agent under the token policy.
        uint256 agentGatedBefore = gated.balanceOf(agent);
        treasury.transferToken(address(gated), agent, gatedFee);
        assertEq(gated.balanceOf(agent), agentGatedBefore + gatedFee);
        assertEq(gated.balanceOf(address(treasury)), treasuryGatedBefore);

        vm.expectRevert(
            abi.encodeWithSelector(AgenticTreasury.GatedRecipientNotAgent.selector, address(gated), nonAgent)
        );
        treasury.transferToken(address(gated), nonAgent, 1);

        // The public quote fee is unrestricted and can move to a non-agent.
        uint256 nonAgentQuoteBefore = quote.balanceOf(nonAgent);
        treasury.transferToken(address(quote), nonAgent, quoteFee);
        assertEq(quote.balanceOf(nonAgent), nonAgentQuoteBefore + quoteFee);
        assertEq(quote.balanceOf(address(treasury)), treasuryQuoteBefore);
    }

    function testNpmAgentCollectsLpFeesToAgentOnly() public {
        (uint256 tokenId,,,) = _mintLp(agent, agent);
        _swapAs(agent, address(gated), address(quote), agent2, SWAP_AMOUNT);
        _swapAs(agent, address(quote), address(gated), agent2, SWAP_AMOUNT);

        uint256 agentGatedBefore = gated.balanceOf(agent);
        uint256 agentQuoteBefore = quote.balanceOf(agent);

        vm.prank(agent);
        (uint256 amount0, uint256 amount1) = npm.collect(
            ICrossVersionNpm.CollectParams({
                tokenId: tokenId, recipient: agent, amount0Max: type(uint128).max, amount1Max: type(uint128).max
            })
        );

        uint256 gatedCollected = gatedIsToken0 ? amount0 : amount1;
        uint256 quoteCollected = gatedIsToken0 ? amount1 : amount0;
        assertGt(gatedCollected, 0);
        assertGt(quoteCollected, 0);
        assertEq(gated.balanceOf(agent), agentGatedBefore + gatedCollected);
        assertEq(quote.balanceOf(agent), agentQuoteBefore + quoteCollected);

        // Even after the fees are cleared, a non-agent recipient is rejected by
        // the gate before any pool interaction.
        vm.prank(agent);
        vm.expectRevert(ERR_NOT_AGENT);
        npm.collect(
            ICrossVersionNpm.CollectParams({
                tokenId: tokenId, recipient: nonAgent, amount0Max: type(uint128).max, amount1Max: type(uint128).max
            })
        );
    }

    // ------------------------------------------------------------------
    // No administrative / registry / router bypass
    // ------------------------------------------------------------------

    function testNoAdminOrRegistryBypassInPath() public {
        // Peripheral contracts expose only immutable wiring, no admin surface.
        assertEq(swapRouter.factory(), address(v3Factory));
        assertEq(swapRouter.WETH9(), address(weth9));
        assertEq(quoter.factory(), address(v3Factory));
        assertEq(npm.factory(), address(v3Factory));
        assertEq(npm.WETH9(), address(weth9));

        // The NPM's policy is the live root registry entry, not a local list.
        assertEq(npm.policyOfToken(address(gated)), address(policy));

        // Gated token: no post-construction mint/admin/pause path.
        _assertNoFunction(address(gated), "mint(address,uint256)");
        _assertNoFunction(address(gated), "owner()");
        _assertNoFunction(address(gated), "pause()");
        _assertNoFunction(address(gated), "setPolicy(address)");
        _assertNoFunction(address(gated), "upgradeTo(address)");

        // The fixed periphery/NPM have no policy/registry/router setters.
        _assertNoFunction(address(swapRouter), "owner()");
        _assertNoFunction(address(swapRouter), "admin()");
        _assertNoFunction(address(swapRouter), "setAssetRegistry(address)");
        _assertNoFunction(address(swapRouter), "setPolicy(address)");
        _assertNoFunction(address(swapRouter), "setRouter(address)");
        _assertNoFunction(address(swapRouter), "setFactory(address)");
        _assertNoFunction(address(swapRouter), "pause()");
        _assertNoFunction(address(quoter), "owner()");
        _assertNoFunction(address(quoter), "setAssetRegistry(address)");
        _assertNoFunction(address(quoter), "setPolicy(address)");
        _assertNoFunction(address(quoter), "setFactory(address)");
        _assertNoFunction(address(npm), "owner()");
        _assertNoFunction(address(npm), "setAssetRegistry(address)");
        _assertNoFunction(address(npm), "setPolicy(address)");
        _assertNoFunction(address(npm), "setRouter(address)");
        _assertNoFunction(address(npm), "setFactory(address)");
        _assertNoFunction(address(npm), "setTreasury(address)");
        _assertNoFunction(address(npm), "pause()");

        // The wrapper has no canonical-factory / registry / router setter.
        _assertNoFunction(address(gatedFactory), "setCanonicalFactory(address)");
        _assertNoFunction(address(gatedFactory), "setAssetRegistry(address)");
        _assertNoFunction(address(gatedFactory), "setQuoteAssetRegistry(address)");
        _assertNoFunction(address(gatedFactory), "setRouter(address)");
        assertEq(gatedFactory.treasury(), address(treasury));
    }

    function _assertPosition(uint256 tokenId, uint128 expectedLiquidity) private view {
        (
            ,,
            address positionToken0,
            address positionToken1,
            uint24 positionFee,
            int24 tickLower,
            int24 tickUpper,
            uint128 positionLiquidity,,,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = npm.positions(tokenId);

        assertEq(positionToken0, token0);
        assertEq(positionToken1, token1);
        assertEq(uint256(positionFee), uint256(FEE));
        assertEq(int256(tickLower), int256(MIN_TICK));
        assertEq(int256(tickUpper), int256(MAX_TICK));
        assertEq(uint256(positionLiquidity), uint256(expectedLiquidity));
        assertEq(uint256(tokensOwed0), 0);
        assertEq(uint256(tokensOwed1), 0);
    }
}

// ---------------------------------------------------------------------------
// Gated-aware AgentswapQuoter (cross-version fork)
// ---------------------------------------------------------------------------

/// @notice cross-version AgentswapQuoter fork: the simulated payout goes to `msg.sender`, so a
/// gated-output quote follows the caller's token policy exactly like execution.
/// Gated-input/public-output and public/public quotes remain caller-agnostic.
contract CrossVersionQuoterTest is CrossVersionDexFixture {
    function testQuoterGatedOutputAgentMatchesExecution() public {
        _mintLp(agent, agent);

        uint256 agentGatedBefore = gated.balanceOf(agent);
        uint256 quoted = _quoteAs(agent, address(quote), address(gated), SWAP_AMOUNT);
        assertGt(quoted, 0);
        assertLt(quoted, SWAP_AMOUNT);
        // The simulated gated payout to the agent was unwound by the callback.
        assertEq(gated.balanceOf(agent), agentGatedBefore);

        uint256 agent2GatedBefore = gated.balanceOf(agent2);
        uint256 executed = _swapAs(agent, address(quote), address(gated), agent2, SWAP_AMOUNT);
        assertEq(executed, quoted);
        assertEq(gated.balanceOf(agent2), agent2GatedBefore + quoted);
    }

    function testQuoterGatedOutputNonAgentReverts() public {
        _mintLp(agent, agent);

        (uint160 sqrtBefore,,,,,,) = v3Pool.slot0();
        uint256 poolGatedBefore = gated.balanceOf(poolAddress);

        vm.prank(nonAgent);
        vm.expectRevert(_errorString("TF"));
        quoter.quoteExactInputSingle(address(quote), address(gated), FEE, SWAP_AMOUNT, 0);

        // The policy denial unwinds the whole simulation.
        (uint160 sqrtAfter,,,,,,) = v3Pool.slot0();
        assertEq(uint256(sqrtAfter), uint256(sqrtBefore));
        assertEq(gated.balanceOf(poolAddress), poolGatedBefore);
        assertEq(gated.balanceOf(nonAgent), 0);
    }

    function testQuoterGatedInputPublicOutputWorksForAnyCaller() public {
        _mintLp(agent, agent);

        uint256 quotedAgent = _quoteAs(agent, address(gated), address(quote), SWAP_AMOUNT);
        uint256 quotedNonAgent = _quoteAs(nonAgent, address(gated), address(quote), SWAP_AMOUNT);
        assertGt(quotedAgent, 0);
        assertEq(quotedNonAgent, quotedAgent);

        uint256 agent2QuoteBefore = quote.balanceOf(agent2);
        uint256 executed = _swapAs(agent, address(gated), address(quote), agent2, SWAP_AMOUNT);
        assertEq(executed, quotedAgent);
        assertEq(quote.balanceOf(agent2), agent2QuoteBefore + executed);
    }

    function testDirectCanonicalCreationReverts() public {
        MockToken a = new MockToken();
        MockToken b = new MockToken();
        (address tokenA, address tokenB) = address(a) < address(b) ? (address(a), address(b)) : (address(b), address(a));

        // The wrapper owns the gated canonical factory; direct creation by any
        // other account is impossible, so a public-public pool cannot bypass it.
        vm.expectRevert();
        v3Factory.createPool(tokenA, tokenB, FEE);
    }
}

// ---------------------------------------------------------------------------
// Gate boundary and documented raw-mint residual
// ---------------------------------------------------------------------------

/// @notice cross-version gate boundary: non-agent/facility LP NFT paths and the raw
/// `pool.mint` residual that cannot be closed without changing the V3 core.
contract CrossVersionGateTest is CrossVersionDexFixture {
    function testNpmGateRejectsNonAgentTransferAndFacility() public {
        (uint256 tokenId,,,) = _mintLp(agent, agent);

        vm.prank(agent);
        vm.expectRevert(ERR_TRANSFER);
        npm.transferFrom(agent, nonAgent, tokenId);

        // A facility is never an agent even when it also holds an Agent ID:
        // the venue category (CUSTODY) takes precedence over identity.
        agentId.setIdentity(address(vault), "vault-agent");
        assertTrue(policy.isMember(address(vault)));
        assertEq(uint256(policy.categoryOf(address(vault))), uint256(FacilityCategory.CUSTODY));
        assertFalse(npm.isAllowedRecipient(address(gated), address(vault)));

        vm.prank(agent);
        vm.expectRevert(ERR_TRANSFER);
        npm.transferFrom(agent, address(vault), tokenId);
    }

    function testNpmGateRejectsNonAgentCollectAndFacilityLp() public {
        (uint256 tokenId,,,) = _mintLp(agent, agent);

        // Approved non-agent caller: ERC-721 auth passes, the agent gate fails.
        vm.prank(agent);
        npm.approve(nonAgent, tokenId);
        vm.prank(nonAgent);
        vm.expectRevert(ERR_OWNER_CALLER);
        npm.collect(
            ICrossVersionNpm.CollectParams({
                tokenId: tokenId, recipient: agent, amount0Max: type(uint128).max, amount1Max: type(uint128).max
            })
        );

        // Agent owner collecting to a non-agent recipient.
        vm.prank(agent);
        vm.expectRevert(ERR_NOT_AGENT);
        npm.collect(
            ICrossVersionNpm.CollectParams({
                tokenId: tokenId, recipient: nonAgent, amount0Max: type(uint128).max, amount1Max: type(uint128).max
            })
        );

        // Facility cannot LP, even with an Agent ID.
        agentId.setIdentity(address(vault), "vault-agent");
        assertTrue(policy.isMember(address(vault)));
        vm.prank(address(vault));
        vm.expectRevert(ERR_NOT_AGENT);
        npm.mint(_mintParams(address(vault)));

        vm.prank(address(vault));
        vm.expectRevert(ERR_NOT_AGENT);
        npm.mint(_mintParams(agent));
    }

    /// @dev Residual, not fixable without a V3-core change: `pool.mint` is
    /// permissionless and has no protocol policy hook, so a raw (non-NPM) position can
    /// be created with a non-agent as the position owner. The token policy still
    /// prevents the gated side from being paid out to that non-agent, so this is
    /// an LP-NFT-gate bypass, not a gated-token transfer bypass.
    function testRawPoolMintResidualBypassesNpmGate() public {
        v3Pool.mint(nonAgent, MIN_TICK, MAX_TICK, RAW_LIQUIDITY, abi.encode(agent));

        // No NPM LP NFT exists for this position.
        assertEq(npm.balanceOf(nonAgent), 0);
        (uint128 rawLiquidity,,) = _poolPosition(nonAgent);
        assertEq(uint256(rawLiquidity), uint256(RAW_LIQUIDITY));

        // Generate gated LP fees for the raw full-range position.
        _swapAs(agent, address(gated), address(quote), agent2, SWAP_AMOUNT);

        // Only the position owner can poke/collect its raw position.
        vm.prank(nonAgent);
        v3Pool.burn(MIN_TICK, MAX_TICK, 0);
        (uint128 rawLiquidityAfter, uint128 tokensOwed0, uint128 tokensOwed1) = _poolPosition(nonAgent);
        assertEq(uint256(rawLiquidityAfter), uint256(RAW_LIQUIDITY));
        uint256 gatedOwed = gatedIsToken0 ? tokensOwed0 : tokensOwed1;
        assertGt(gatedOwed, 0);

        // The attempt to pay the gated fee to the non-agent owner reverts in the
        // token policy ('TF' from the V3 core transfer helper).
        vm.prank(nonAgent);
        vm.expectRevert(_errorString("TF"));
        v3Pool.collect(nonAgent, MIN_TICK, MAX_TICK, type(uint128).max, type(uint128).max);
        assertEq(gated.balanceOf(nonAgent), 0);
    }
}
