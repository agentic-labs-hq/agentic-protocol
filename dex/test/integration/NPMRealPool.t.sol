// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import {UniswapV3Factory} from "@uniswap/v3-core/contracts/UniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TestERC20} from "@uniswap/v3-core/contracts/test/TestERC20.sol";

import {AgentswapPositionManager} from "../../contracts/AgentswapPositionManager.sol";
import {INonfungiblePositionManager} from "../../contracts/interfaces/INonfungiblePositionManager.sol";

import {TestBase} from "../helpers/TestBase.sol";
import {MockAssetRegistry} from "../mocks/MockAssetRegistry.sol";
import {MockTransferPolicy} from "../mocks/MockTransferPolicy.sol";

/// @notice End-to-end NPM gate path against a real local V3 core pool.
/// @dev Proves the deployment-specific `PoolAddress` constant resolves the
/// factory-created pool and the actual addLiquidity/mint callback works, not
/// just the etched mock. One gated + one quote token; gated/gated policy
/// combinations are covered in `test/unit/NPMGate.t.sol`.
contract NPMRealPoolTest is TestBase {
    uint24 private constant FEE = 3000;
    int24 private constant MIN_TICK = -887220;
    int24 private constant MAX_TICK = 887220;
    uint160 private constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint256 private constant MINT_AMOUNT = 1e18;

    uint8 private constant CAT_LP_MANAGER = 2;
    uint8 private constant CAT_CUSTODY = 4;

    bytes4 private constant ERR_NOT_AGENT = bytes4(keccak256("NotAgent()"));

    address private constant AGENT = address(0xA11CE);
    address private constant NON_AGENT = address(0xBAD);
    address private constant FACILITY = address(0xFAC11);

    UniswapV3Factory private factory;
    MockAssetRegistry private registry;
    MockTransferPolicy private policy;
    AgentswapPositionManager private npm;

    TestERC20 private tokenA;
    TestERC20 private tokenB;
    address private token0;
    address private token1;
    address private gatedToken;

    function setUp() public {
        factory = new UniswapV3Factory();
        registry = new MockAssetRegistry();
        policy = new MockTransferPolicy();

        npm = AgentswapPositionManager(
            payable(vm.deployCode(
                    "AgentswapPositionManager.sol:AgentswapPositionManager",
                    abi.encode(address(factory), address(0xBEEF), address(0), address(registry))
                ))
        );

        tokenA = new TestERC20(1e30);
        tokenB = new TestERC20(1e30);
        (token0, token1) = _sort(address(tokenA), address(tokenB));
        gatedToken = address(tokenA);

        policy.setMember(address(this), true);
        policy.setMember(AGENT, true);
        policy.setMember(address(npm), true);
        policy.setCategory(address(npm), CAT_LP_MANAGER);
        policy.setMember(FACILITY, true);
        policy.setCategory(FACILITY, CAT_CUSTODY);

        registry.setRegistered(gatedToken, true);
        registry.setPolicy(gatedToken, address(policy));

        address pool = factory.createPool(token0, token1, FEE);
        IUniswapV3Pool(pool).initialize(SQRT_PRICE_1_1);

        tokenA.approve(address(npm), uint256(-1));
        tokenB.approve(address(npm), uint256(-1));
    }

    function testMintAgentRealPoolWorks() public {
        uint256 tokenId = _mint(AGENT);
        assertEq(npm.ownerOf(tokenId), AGENT);
        assertTrue(_liquidity(tokenId) > 0);
    }

    function testMintNonAgentRealPoolReverts() public {
        expectRevertSelector(ERR_NOT_AGENT);
        _mint(NON_AGENT);
    }

    function testDecreaseAndCollectRealPool() public {
        uint256 tokenId = _mint(AGENT);
        uint128 liquidity = _liquidity(tokenId);

        vm.prank(AGENT);
        npm.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId, liquidity: liquidity, amount0Min: 0, amount1Min: 0, deadline: uint256(-1)
            })
        );
        assertEq(uint256(_liquidity(tokenId)), 0);

        vm.prank(AGENT);
        (uint256 amount0, uint256 amount1) = npm.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId, recipient: AGENT, amount0Max: uint128(-1), amount1Max: uint128(-1)
            })
        );
        assertTrue(amount0 > 0 && amount1 > 0);
    }

    function _mint(address recipient) private returns (uint256 tokenId) {
        (tokenId,,,) = npm.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: FEE,
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                amount0Desired: MINT_AMOUNT,
                amount1Desired: MINT_AMOUNT,
                amount0Min: 0,
                amount1Min: 0,
                recipient: recipient,
                deadline: uint256(-1)
            })
        );
    }

    function _liquidity(uint256 tokenId) private view returns (uint128 liquidity) {
        (,,,,,,, liquidity,,,,) = npm.positions(tokenId);
    }

    function _sort(address a, address b) private pure returns (address a0, address a1) {
        if (a < b) return (a, b);
        return (b, a);
    }
}
