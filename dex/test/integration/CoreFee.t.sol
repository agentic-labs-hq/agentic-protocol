// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import {IERC20Minimal} from "@uniswap/v3-core/contracts/interfaces/IERC20Minimal.sol";

import {RealCoreFixture} from "../helpers/RealCoreFixture.sol";

/// @notice Protocol-fee evidence on a real local V3 core pool: `(8,8)` is set
/// by the factory owner (in production the AgentswapPoolFactory owns the canonical
/// factory), swaps accrue fees on both sides and `collectProtocol` pays the
/// treasury address.
/// @dev This is the 0.7.6 core side of the fee integration. The 0.8.20 treasury contract and
/// the gated-token fee path are cross-version and belong to the gated fork; here the
/// recipient is a dedicated public address.
contract CoreFeeTest is RealCoreFixture {
    uint8 private constant PROTOCOL_FEE = 8;

    /// @dev Stand-in treasury recipient. A plain address is intentional: the
    /// core `collectProtocol` transfer is token-generic and the protocol
    /// `AgenticTreasury` (0.8.20) cannot be compiled into this project.
    address private constant TREASURY = address(0x7BEA5);

    function setUp() public {
        _deployCore();
        // The test contract deployed the real factory, so it is the owner that
        // the pool's `onlyFactoryOwner` modifier checks (production: the gated
        // wrapper, which sets (8,8) atomically at pool creation).
        pool.setFeeProtocol(PROTOCOL_FEE, PROTOCOL_FEE);
        _addLiquidity();
    }

    function testProtocolFeeIsEightOnBothSides() public {
        (uint160 sqrtPriceX96,,,,, uint8 feeProtocol, bool unlocked) = pool.slot0();
        assertTrue(sqrtPriceX96 > 0);
        assertTrue(unlocked);
        assertEq(feeProtocol, uint8(0x88));
    }

    function testOnlyFactoryOwnerCanSetFeeProtocol() public {
        vm.prank(NON_OWNER);
        vm.expectRevert();
        pool.setFeeProtocol(4, 4);

        // The owner still cannot set an out-of-range side (core requires 0 or
        // [4,10]); the pool keeps (8,8).
        vm.expectRevert();
        pool.setFeeProtocol(3, PROTOCOL_FEE);

        (,,,,, uint8 feeProtocol,) = pool.slot0();
        assertEq(feeProtocol, uint8(0x88));
    }

    function testProtocolFeesAccrueBothSidesAndCollectToTreasury() public {
        // One full single-step swap of SWAP_AMOUNT at the 0.3% tier: the LP fee
        // is SWAP_AMOUNT * 0.003, and (8,8) takes 1/8 of it per side.
        uint128 expectedProtocolFee = uint128((SWAP_AMOUNT * FEE / 1e6) / PROTOCOL_FEE);
        assertTrue(expectedProtocolFee > 0);

        (uint128 fee0Before, uint128 fee1Before) = pool.protocolFees();
        assertEq(fee0Before, 0);
        assertEq(fee1Before, 0);

        // token0 in: only the token0 side can accrue protocol fees.
        _exactInputSingle(token0, token1, RECIPIENT, SWAP_AMOUNT, 0, block.timestamp);
        (uint128 fee0AfterFirst, uint128 fee1AfterFirst) = pool.protocolFees();
        assertEq(fee0AfterFirst, expectedProtocolFee);
        assertEq(fee1AfterFirst, 0);

        // token1 in: now the token1 side accrues; the token0 side is unchanged.
        _exactInputSingle(token1, token0, RECIPIENT, SWAP_AMOUNT, 0, block.timestamp);
        (uint128 fee0, uint128 fee1) = pool.protocolFees();
        assertEq(fee0, fee0AfterFirst);
        assertEq(fee1, expectedProtocolFee);

        // The router never custodies the fees.
        assertEq(IERC20Minimal(token0).balanceOf(address(swapRouter)), 0);
        assertEq(IERC20Minimal(token1).balanceOf(address(swapRouter)), 0);

        uint256 treasury0Before = IERC20Minimal(token0).balanceOf(TREASURY);
        uint256 treasury1Before = IERC20Minimal(token1).balanceOf(TREASURY);
        uint256 pool0Before = IERC20Minimal(token0).balanceOf(address(pool));
        uint256 pool1Before = IERC20Minimal(token1).balanceOf(address(pool));

        // Only the canonical factory owner may collect. The production owner is
        // the gated wrapper; an arbitrary caller cannot redirect the fees.
        vm.prank(NON_OWNER);
        vm.expectRevert();
        pool.collectProtocol(NON_OWNER, uint128(-1), uint128(-1));

        (uint128 collected0, uint128 collected1) = pool.collectProtocol(TREASURY, uint128(-1), uint128(-1));

        // Core leaves one unit in each slot (gas optimisation), so the returned
        // amounts are the accrued amounts minus one.
        assertEq(collected0, fee0 - 1);
        assertEq(collected1, fee1 - 1);
        assertTrue(collected0 > 0);
        assertTrue(collected1 > 0);

        assertEq(IERC20Minimal(token0).balanceOf(TREASURY), treasury0Before + collected0);
        assertEq(IERC20Minimal(token1).balanceOf(TREASURY), treasury1Before + collected1);
        assertEq(IERC20Minimal(token0).balanceOf(address(pool)), pool0Before - collected0);
        assertEq(IERC20Minimal(token1).balanceOf(address(pool)), pool1Before - collected1);

        (uint128 remaining0, uint128 remaining1) = pool.protocolFees();
        assertEq(remaining0, 1);
        assertEq(remaining1, 1);
    }
}
