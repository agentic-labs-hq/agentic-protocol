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

import {TestBase} from "./TestBase.sol";
import {MockAssetRegistry} from "../mocks/MockAssetRegistry.sol";

/// @notice Shared fixture for real 0.7.6 core + standard periphery integration
/// tests: an actual `UniswapV3Factory`/pool, an NPM minted full-range position
/// and the unmodified `AgentswapRouter`/`AgentswapQuoter` built against this project.
/// @dev The NPM asset registry is intentionally empty here: these are public
/// test tokens, so `policyOfToken` resolves to `address(0)` and the the NPM NPM
/// gate is inert (the same state as a non-gated quote token in production).
/// Gated-token behaviour is exercised in `NPMGate`/`NPMRealPool` and, cross
/// version, in the gated fork.
abstract contract RealCoreFixture is TestBase {
    uint24 internal constant FEE = 3000;
    int24 internal constant MIN_TICK = -887220;
    int24 internal constant MAX_TICK = 887220;
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    uint256 internal constant TOKEN_SUPPLY = 1e30;
    uint256 internal constant LP_AMOUNT = 1e21;
    uint256 internal constant SWAP_AMOUNT = 1e18;

    /// @dev No mainnet address: the router/quoter never use WETH9 on this path.
    address internal constant WETH9 = address(0xBEEF);

    address internal constant RECIPIENT = address(0xB0B);
    address internal constant NON_OWNER = address(0xBAD);

    UniswapV3Factory internal factory;
    IUniswapV3Pool internal pool;
    TestERC20 internal tokenA;
    TestERC20 internal tokenB;
    address internal token0;
    address internal token1;
    AgentswapPositionManager internal npm;
    AgentswapRouter internal swapRouter;
    AgentswapQuoter internal quoter;

    function _deployCore() internal {
        factory = new UniswapV3Factory();

        tokenA = new TestERC20(TOKEN_SUPPLY);
        tokenB = new TestERC20(TOKEN_SUPPLY);
        (token0, token1) = _sort(address(tokenA), address(tokenB));

        pool = IUniswapV3Pool(factory.createPool(token0, token1, FEE));
        pool.initialize(SQRT_PRICE_1_1);

        MockAssetRegistry registry = new MockAssetRegistry();
        npm = AgentswapPositionManager(
            payable(vm.deployCode(
                    "AgentswapPositionManager.sol:AgentswapPositionManager",
                    abi.encode(address(factory), WETH9, address(0), address(registry))
                ))
        );

        swapRouter = AgentswapRouter(
            payable(vm.deployCode("AgentswapRouter.sol:AgentswapRouter", abi.encode(address(factory), WETH9)))
        );
        quoter =
            AgentswapQuoter(vm.deployCode("AgentswapQuoter.sol:AgentswapQuoter", abi.encode(address(factory), WETH9)));

        IERC20Minimal(token0).approve(address(npm), uint256(-1));
        IERC20Minimal(token1).approve(address(npm), uint256(-1));
        IERC20Minimal(token0).approve(address(swapRouter), uint256(-1));
        IERC20Minimal(token1).approve(address(swapRouter), uint256(-1));
    }

    /// @dev Mints a full-range position at the 1:1 start price. The NPM is
    /// deployed with an empty registry, so no policy gate applies.
    function _addLiquidity() internal returns (uint256 tokenId) {
        (tokenId,,,) = npm.mint(
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

    function _exactInputSingle(
        address tokenIn,
        address tokenOut,
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) internal returns (uint256 amountOut) {
        amountOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: FEE,
                recipient: recipient,
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function _quoteExactInputSingle(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        amountOut = quoter.quoteExactInputSingle(tokenIn, tokenOut, FEE, amountIn, 0);
    }

    function _sort(address a, address b) private pure returns (address a0, address a1) {
        if (a < b) return (a, b);
        return (b, a);
    }
}
