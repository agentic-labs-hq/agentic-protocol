// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal local ABI for the Uniswap V3 `SwapRouter` (deployed as
/// `AgentswapRouter`) `exactInputSingle` path.
/// @dev the protocol has no V3 dependency and no cross-version structs; this is the
/// 0.8.x-compatible ABI only (field order matches the pinned 0.7.6 router).
/// Only the single-hop exact-input path used by the treasury is declared.
interface ISwapRouter {
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
}
