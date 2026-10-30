// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISwapRouter} from "../../contracts/treasury/ISwapRouter.sol";

/// @notice Configurable `ISwapRouter` mock for the treasury swap tests.
/// @dev Records every parameter the treasury passes, including the allowance it
/// observed before pulling the input token. `amountOut` is returned unchanged so
/// the treasury's own `amountOutMinimum` check is exercised.
contract MockSwapRouter is ISwapRouter {
    using SafeERC20 for IERC20;

    error MockSwapReverted();

    uint256 public amountOut;
    bool public pullTokens = true;
    bool public revertOnSwap;

    uint256 public callCount;
    address public lastTokenIn;
    address public lastTokenOut;
    uint24 public lastFee;
    address public lastRecipient;
    uint256 public lastDeadline;
    uint256 public lastAmountIn;
    uint256 public lastAmountOutMinimum;
    uint160 public lastSqrtPriceLimitX96;
    uint256 public lastAllowanceSeen;

    function setAmountOut(uint256 amountOut_) external {
        amountOut = amountOut_;
    }

    function setPullTokens(bool pullTokens_) external {
        pullTokens = pullTokens_;
    }

    function setRevertOnSwap(bool revertOnSwap_) external {
        revertOnSwap = revertOnSwap_;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable override returns (uint256) {
        if (revertOnSwap) revert MockSwapReverted();

        callCount++;
        lastTokenIn = params.tokenIn;
        lastTokenOut = params.tokenOut;
        lastFee = params.fee;
        lastRecipient = params.recipient;
        lastDeadline = params.deadline;
        lastAmountIn = params.amountIn;
        lastAmountOutMinimum = params.amountOutMinimum;
        lastSqrtPriceLimitX96 = params.sqrtPriceLimitX96;
        lastAllowanceSeen = IERC20(params.tokenIn).allowance(msg.sender, address(this));

        if (pullTokens) {
            IERC20(params.tokenIn).safeTransferFrom(msg.sender, params.recipient, params.amountIn);
        }

        return amountOut;
    }
}
