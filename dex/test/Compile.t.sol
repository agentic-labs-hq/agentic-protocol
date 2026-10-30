// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

// the compile smoke compile smoke only: imports pinned Uniswap V3 core and periphery entry
// points. No behavior tests at the compile smoke.
// Named imports keep the core and periphery `TransferHelper` libraries, which
// share a name, out of the file-level symbol namespace.
import {UniswapV3Factory} from "@uniswap/v3-core/contracts/UniswapV3Factory.sol";
import {UniswapV3Pool} from "@uniswap/v3-core/contracts/UniswapV3Pool.sol";
import {AgentswapPositionManager} from "@uniswap/v3-periphery/contracts/AgentswapPositionManager.sol";
import {
    NonfungibleTokenPositionDescriptor
} from "@uniswap/v3-periphery/contracts/NonfungibleTokenPositionDescriptor.sol";
import {AgentswapRouter} from "@uniswap/v3-periphery/contracts/AgentswapRouter.sol";
import {AgentswapQuoter} from "@uniswap/v3-periphery/contracts/lens/AgentswapQuoter.sol";

contract CompileTest {
    function testBaselineCompiles() public pure {
        assert(true);
    }
}
