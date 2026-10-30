// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal owner getter used to mirror the canonical pool's
/// `onlyFactoryOwner` check without importing the factory mock.
interface IMockV3FactoryOwner {
    function owner() external view returns (address);
}

/// @notice V3-pool-shaped mock for the `AgentswapPoolFactory` unit tests.
/// @dev Stores initialization/protocol-fee/collect calls so tests can assert the
/// wrapper performed each step exactly once and always paid the treasury. The
/// factory-owner check mirrors the canonical pool's `onlyFactoryOwner`.
contract MockV3Pool {
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    int24 public immutable tickSpacing;

    uint160 public sqrtPriceX96;
    uint8 public feeProtocol0;
    uint8 public feeProtocol1;
    uint128 public protocolFees0;
    uint128 public protocolFees1;

    address public collectRecipient;
    uint128 public collectAmount0Requested;
    uint128 public collectAmount1Requested;

    uint256 public initializeCalls;
    uint256 public setFeeProtocolCalls;
    uint256 public collectProtocolCalls;

    error AlreadyInitialized();
    error NotFactoryOwner(address caller);
    error InvalidFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1);

    constructor(address factory_, address token0_, address token1_, uint24 fee_, int24 tickSpacing_) {
        factory = factory_;
        token0 = token0_;
        token1 = token1_;
        fee = fee_;
        tickSpacing = tickSpacing_;
    }

    function initialize(uint160 sqrtPriceX96_) external {
        if (sqrtPriceX96 != 0) revert AlreadyInitialized();
        sqrtPriceX96 = sqrtPriceX96_;
        initializeCalls++;
    }

    function setFeeProtocol(uint8 feeProtocol0_, uint8 feeProtocol1_) external {
        if (msg.sender != IMockV3FactoryOwner(factory).owner()) revert NotFactoryOwner(msg.sender);
        if (
            (feeProtocol0_ != 0 && (feeProtocol0_ < 4 || feeProtocol0_ > 10))
                || (feeProtocol1_ != 0 && (feeProtocol1_ < 4 || feeProtocol1_ > 10))
        ) revert InvalidFeeProtocol(feeProtocol0_, feeProtocol1_);

        feeProtocol0 = feeProtocol0_;
        feeProtocol1 = feeProtocol1_;
        setFeeProtocolCalls++;
    }

    function collectProtocol(address recipient, uint128 amount0Requested, uint128 amount1Requested)
        external
        returns (uint128 amount0, uint128 amount1)
    {
        if (msg.sender != IMockV3FactoryOwner(factory).owner()) revert NotFactoryOwner(msg.sender);

        collectRecipient = recipient;
        collectAmount0Requested = amount0Requested;
        collectAmount1Requested = amount1Requested;
        collectProtocolCalls++;

        amount0 = amount0Requested > protocolFees0 ? protocolFees0 : amount0Requested;
        amount1 = amount1Requested > protocolFees1 ? protocolFees1 : amount1Requested;
        protocolFees0 -= amount0;
        protocolFees1 -= amount1;
    }

    /// @dev Test hook: seed the protocol fees the pool can pay out.
    function setProtocolFees(uint128 protocolFees0_, uint128 protocolFees1_) external {
        protocolFees0 = protocolFees0_;
        protocolFees1 = protocolFees1_;
    }
}
