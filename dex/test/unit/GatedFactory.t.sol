// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import {AgentswapV3Factory} from "../../contracts/factories/AgentswapV3Factory.sol";
import {UniswapV3Pool} from "@uniswap/v3-core/contracts/UniswapV3Pool.sol";
import {TestERC20} from "@uniswap/v3-core/contracts/test/TestERC20.sol";

import {PoolAddress} from "../../contracts/libraries/PoolAddress.sol";
import {TestBase} from "../helpers/TestBase.sol";

/// @notice M4: the gated factory only lets the owner (the root wrapper) create
/// pools, while pool bytecode/address derivation stay upstream-compatible.
contract GatedFactoryTest is TestBase {
    uint24 private constant FEE = 3000;

    AgentswapV3Factory private factory;
    TestERC20 private tokenA;
    TestERC20 private tokenB;

    function setUp() public {
        factory = new AgentswapV3Factory();
        tokenA = new TestERC20(0);
        tokenB = new TestERC20(0);
    }

    function testOwnerAndDefaultTiers() public {
        assertEq(factory.owner(), address(this));
        assertEq(uint256(uint24(factory.feeAmountTickSpacing(500))), 10);
        assertEq(uint256(uint24(factory.feeAmountTickSpacing(3000))), 60);
        assertEq(uint256(uint24(factory.feeAmountTickSpacing(10000))), 200);
    }

    function testOnlyOwnerCanCreate() public {
        (address token0, address token1) = _sort(address(tokenA), address(tokenB));

        vm.prank(address(0xBEEF));
        vm.expectRevert();
        factory.createPool(token0, token1, FEE);
    }

    function testOwnerCreatesAndAddressMatchesLocalPoolHash() public {
        (address token0, address token1) = _sort(address(tokenA), address(tokenB));

        address pool = factory.createPool(token0, token1, FEE);
        assertEq(pool, factory.getPool(token0, token1, FEE));
        assertEq(pool, factory.getPool(token1, token0, FEE));

        PoolAddress.PoolKey memory key = PoolAddress.PoolKey({token0: token0, token1: token1, fee: FEE});
        assertEq(PoolAddress.computeAddress(address(factory), key), pool);
        assertTrue(keccak256(type(UniswapV3Pool).creationCode) == PoolAddress.POOL_INIT_CODE_HASH);
    }

    function testOwnerHandoffRestrictsNewOwner() public {
        vm.expectRevert();
        vm.prank(address(0xBEEF));
        factory.setOwner(address(0xBEEF));

        factory.setOwner(address(0xBEEF));
        assertEq(factory.owner(), address(0xBEEF));

        (address token0, address token1) = _sort(address(tokenA), address(tokenB));
        vm.expectRevert();
        factory.createPool(token0, token1, FEE);

        vm.prank(address(0xBEEF));
        address pool = factory.createPool(token0, token1, FEE);
        assertEq(pool, factory.getPool(token0, token1, FEE));
    }

    function testFeeTierAddOnlyOwner() public {
        vm.expectRevert();
        vm.prank(address(0xBEEF));
        factory.enableFeeAmount(100, 1);

        factory.enableFeeAmount(100, 1);
        assertEq(uint256(uint24(factory.feeAmountTickSpacing(100))), 1);
    }

    function _sort(address a, address b) private pure returns (address token0, address token1) {
        if (a < b) return (a, b);
        return (b, a);
    }
}
