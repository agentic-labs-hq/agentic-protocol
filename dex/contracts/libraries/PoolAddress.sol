// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Provides functions for deriving a pool address from the factory, tokens, and the fee
library PoolAddress {
    /// @dev Deployment-specific fork constant, NOT the upstream v3-periphery value.
    /// The local `UniswapV3Pool` is compiled from the vendored upstream source
    /// with this project's solc 0.7.6 / optimizer-runs 200 profile, so its
    /// creation-code hash differs from the upstream canonical 800-run hash
    /// (0xe34f199b...). It is `keccak256(type(UniswapV3Pool).creationCode)` for
    /// this exact build; `test/unit/PoolAddressRealCore.t.sol` asserts the
    /// factory-created pool address equals `computeAddress` and the hash matches.
    /// Do not "restore" the upstream constant: the NPM/router/quoter would then
    /// compute addresses that do not exist on this deployment.
    bytes32 internal constant POOL_INIT_CODE_HASH = 0xb2635d2e91d517bfbbcc2804c6a779c0f78ca6ee09d8d3f7ba48f1a5c35e5f9e;

    /// @notice The identifying key of the pool
    struct PoolKey {
        address token0;
        address token1;
        uint24 fee;
    }

    /// @notice Returns PoolKey: the ordered tokens with the matched fee levels
    /// @param tokenA The first token of a pool, unsorted
    /// @param tokenB The second token of a pool, unsorted
    /// @param fee The fee level of the pool
    /// @return Poolkey The pool details with ordered token0 and token1 assignments
    function getPoolKey(
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal pure returns (PoolKey memory) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey({token0: tokenA, token1: tokenB, fee: fee});
    }

    /// @notice Deterministically computes the pool address given the factory and PoolKey
    /// @param factory The Uniswap V3 factory contract address
    /// @param key The PoolKey
    /// @return pool The contract address of the V3 pool
    function computeAddress(address factory, PoolKey memory key) internal pure returns (address pool) {
        require(key.token0 < key.token1);
        pool = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex'ff',
                        factory,
                        keccak256(abi.encode(key.token0, key.token1, key.fee)),
                        POOL_INIT_CODE_HASH
                    )
                )
            )
        );
    }
}
