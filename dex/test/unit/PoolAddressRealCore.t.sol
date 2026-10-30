// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import {UniswapV3Factory} from "@uniswap/v3-core/contracts/UniswapV3Factory.sol";
import {UniswapV3Pool} from "@uniswap/v3-core/contracts/UniswapV3Pool.sol";
import {TestERC20} from "@uniswap/v3-core/contracts/test/TestERC20.sol";

import {PoolAddress} from "../../contracts/libraries/PoolAddress.sol";
import {TestBase} from "../helpers/TestBase.sol";

/// @notice Proves the deployment-specific `PoolAddress.POOL_INIT_CODE_HASH`
/// matches the local 0.7.6 core build and reproduces factory pool addresses.
contract PoolAddressRealCoreTest is TestBase {
    uint24 private constant FEE = 3000;

    function testInitCodeHashMatchesLocalCore() public {
        assertTrue(keccak256(type(UniswapV3Pool).creationCode) == PoolAddress.POOL_INIT_CODE_HASH);
        // Explicitly not the upstream 800-run canonical hash.
        assertTrue(
            keccak256(type(UniswapV3Pool).creationCode)
                != 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54
        );
    }

    function testComputeAddressMatchesFactoryPool() public {
        UniswapV3Factory factory = new UniswapV3Factory();
        TestERC20 tokenA = new TestERC20(0);
        TestERC20 tokenB = new TestERC20(0);
        (address token0, address token1) = _sort(address(tokenA), address(tokenB));

        address pool = factory.createPool(token0, token1, FEE);
        PoolAddress.PoolKey memory key = PoolAddress.PoolKey({token0: token0, token1: token1, fee: FEE});

        assertEq(pool, factory.getPool(token0, token1, FEE));
        assertEq(PoolAddress.computeAddress(address(factory), key), pool);
    }

    function _sort(address tokenA, address tokenB) private pure returns (address token0, address token1) {
        if (tokenA < tokenB) return (tokenA, tokenB);
        return (tokenB, tokenA);
    }
}
