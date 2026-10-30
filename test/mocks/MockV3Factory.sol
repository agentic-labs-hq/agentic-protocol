// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockV3Pool} from "./MockV3Pool.sol";

/// @notice V3-factory-shaped mock for the `AgentswapPoolFactory` unit tests.
/// @dev Mirrors the canonical factory's sorting, fee-tier lookup, duplicate
/// rejection, owner transfer and fee-tier enablement. Pools are deployed with
/// `CREATE` (the canonical factory uses `CREATE2`); tests predict the address
/// with Foundry's `computeCreateAddress`.
contract MockV3Factory {
    address public owner;

    mapping(uint24 => int24) public feeAmountTickSpacing;
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;

    uint256 public createPoolCalls;
    uint256 public enableFeeAmountCalls;
    uint256 public setOwnerCalls;

    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event FeeAmountEnabled(uint24 indexed fee, int24 indexed tickSpacing);
    event PoolCreated(
        address indexed token0, address indexed token1, uint24 indexed fee, int24 tickSpacing, address pool
    );

    error NotOwner(address caller);
    error ZeroToken();
    error IdenticalTokens();
    error FeeNotEnabled(uint24 fee);
    error PoolAlreadyExists(address token0, address token1, uint24 fee);
    error FeeTooLarge(uint24 fee);
    error InvalidTickSpacing(int24 tickSpacing);
    error FeeAlreadyEnabled(uint24 fee);

    constructor() {
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);

        _enableFeeAmount(500, 10);
        _enableFeeAmount(3000, 60);
        _enableFeeAmount(10000, 200);
    }

    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool) {
        if (tokenA == tokenB) revert IdenticalTokens();
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroToken();

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        int24 tickSpacing = feeAmountTickSpacing[fee];
        if (tickSpacing == 0) revert FeeNotEnabled(fee);
        if (getPool[token0][token1][fee] != address(0)) revert PoolAlreadyExists(token0, token1, fee);

        pool = address(new MockV3Pool(address(this), token0, token1, fee, tickSpacing));
        getPool[token0][token1][fee] = pool;
        getPool[token1][token0][fee] = pool;
        createPoolCalls++;

        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }

    function setOwner(address newOwner) external {
        if (msg.sender != owner) revert NotOwner(msg.sender);

        address oldOwner = owner;
        owner = newOwner;
        setOwnerCalls++;
        emit OwnerChanged(oldOwner, newOwner);
    }

    function enableFeeAmount(uint24 fee, int24 tickSpacing) external {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _enableFeeAmount(fee, tickSpacing);
    }

    function _enableFeeAmount(uint24 fee, int24 tickSpacing) private {
        if (fee >= 1_000_000) revert FeeTooLarge(fee);
        if (tickSpacing <= 0 || tickSpacing >= 16384) revert InvalidTickSpacing(tickSpacing);
        if (feeAmountTickSpacing[fee] != 0) revert FeeAlreadyEnabled(fee);

        feeAmountTickSpacing[fee] = tickSpacing;
        enableFeeAmountCalls++;
        emit FeeAmountEnabled(fee, tickSpacing);
    }
}
