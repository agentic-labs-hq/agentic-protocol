// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

/// @notice Minimal V3 pool used by the NPM gate tests.
/// @dev Etched at the address the NPM computes via `PoolAddress.computeAddress`
/// so the standard `addLiquidity`/position paths run without a real AMM. It
/// does not move tokens or call the mint callback; it only returns the view /
/// accounting values the NPM consumes. Amounts are mock values, not V3 math.
contract MockV3Pool {
    uint160 private constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function slot0()
        external
        pure
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        return (SQRT_PRICE_1_1, 0, 0, 1, 1, 0, true);
    }

    function mint(address, int24, int24, uint128 amount, bytes calldata)
        external
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        return (uint256(amount), uint256(amount));
    }

    function burn(int24, int24, uint128 amount) external pure returns (uint256 amount0, uint256 amount1) {
        return (uint256(amount), uint256(amount));
    }

    function collect(address, int24, int24, uint128 amount0Requested, uint128 amount1Requested)
        external
        pure
        returns (uint128 amount0, uint128 amount1)
    {
        return (amount0Requested, amount1Requested);
    }

    function positions(bytes32)
        external
        pure
        returns (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        return (0, 0, 0, 0, 0);
    }
}
