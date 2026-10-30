// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Governance2Step} from "../../contracts/common/Governance2Step.sol";
import {FacilityCategory, NPM, POOL, TREASURY} from "../../contracts/common/Types.sol";
import {AgentswapPoolFactory} from "../../contracts/pool/AgentswapPoolFactory.sol";
import {AgenticVenueRegistry} from "../../contracts/registry/AgenticVenueRegistry.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";

import {MockToken} from "../mocks/MockToken.sol";
import {MockV3Factory} from "../mocks/MockV3Factory.sol";
import {MockV3Pool} from "../mocks/MockV3Pool.sol";
import {MockVenueAccount} from "../mocks/MockVenueAccount.sol";
import {TokenAssetFixture} from "../helpers/TokenAssetFixture.sol";

contract AgentswapPoolFactoryTest is TokenAssetFixture {
    event GatedPoolCreated(
        address indexed pool, address indexed token0, address indexed token1, uint24 fee, uint160 sqrtPriceX96
    );
    event ProtocolFeeSet(address indexed pool, uint8 feeProtocol0, uint8 feeProtocol1);
    event ProtocolCollected(address indexed pool, address indexed recipient, uint128 amount0, uint128 amount1);
    event TreasurySet(address indexed treasury);
    event FeeAmountEnabled(uint24 fee, int24 tickSpacing);
    event CanonicalFactoryOwnerChanged(address indexed newOwner);

    uint24 internal constant DEFAULT_FEE = 3000;
    uint160 internal constant DEFAULT_SQRT_PRICE = 79228162514264337593543950336; // 2^96
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    AgentswapPoolFactory internal gatedFactory;
    MockV3Factory internal v3Factory;
    MockVenueAccount internal feeTreasury;
    MockVenueAccount internal feeTreasury2;
    MockToken internal quote;
    MockToken internal quote2;
    AgenticToken internal gated;
    AgenticToken internal gated2;

    function setUp() public {
        _deployTokenAsset();

        v3Factory = new MockV3Factory();

        feeTreasury = new MockVenueAccount();
        feeTreasury2 = new MockVenueAccount();
        venue.registerFacility(address(feeTreasury), TREASURY);
        venue.registerFacility(address(feeTreasury2), TREASURY);

        gatedFactory = new AgentswapPoolFactory(
            address(v3Factory),
            address(assetRegistry),
            address(quoteRegistry),
            address(venue),
            address(policyRegistry),
            address(feeTreasury),
            address(this)
        );
        v3Factory.setOwner(address(gatedFactory));
        venue.setRegistrar(address(gatedFactory), FacilityCategory.POOL, true);

        quote = new MockToken();
        quote2 = new MockToken();
        quoteRegistry.addQuoteAsset(address(quote));
        quoteRegistry.addQuoteAsset(address(quote2));

        gated = AgenticToken(_createTokenFor(address(this), agent, 1_000 ether));
        gated2 = AgenticToken(_createTokenFor(address(this), agent2, 1_000 ether));
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _createPool(address tokenA, address tokenB) internal returns (MockV3Pool pool) {
        pool = _createPool(tokenA, tokenB, DEFAULT_FEE, DEFAULT_SQRT_PRICE);
    }

    function _createPool(address tokenA, address tokenB, uint24 fee, uint160 sqrtPriceX96)
        internal
        returns (MockV3Pool pool)
    {
        pool = MockV3Pool(gatedFactory.createPool(tokenA, tokenB, fee, sqrtPriceX96));
    }

    function _nextPoolAddress() internal view returns (address) {
        return vm.computeCreateAddress(address(v3Factory), vm.getNonce(address(v3Factory)));
    }

    function _sorted(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    // ---------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------

    function testConstructorState() public view {
        assertEq(gatedFactory.governance(), address(this));
        assertEq(gatedFactory.pendingGovernance(), address(0));
        assertEq(gatedFactory.canonicalFactory(), address(v3Factory));
        assertEq(gatedFactory.assetRegistry(), address(assetRegistry));
        assertEq(gatedFactory.quoteAssetRegistry(), address(quoteRegistry));
        assertEq(gatedFactory.venueRegistry(), address(venue));
        assertEq(gatedFactory.policyRegistry(), address(policyRegistry));
        assertEq(gatedFactory.treasury(), address(feeTreasury));
        assertEq(v3Factory.owner(), address(gatedFactory));
    }

    function testConstructorRejectsZeroGovernance() public {
        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        new AgentswapPoolFactory(
            address(v3Factory),
            address(assetRegistry),
            address(quoteRegistry),
            address(venue),
            address(policyRegistry),
            address(feeTreasury),
            address(0)
        );
    }

    function testConstructorRejectsZeroCanonicalFactory() public {
        vm.expectRevert(AgentswapPoolFactory.ZeroCanonicalFactory.selector);
        new AgentswapPoolFactory(
            address(0),
            address(assetRegistry),
            address(quoteRegistry),
            address(venue),
            address(policyRegistry),
            address(feeTreasury),
            address(this)
        );
    }

    function testConstructorRejectsCodelessCanonicalFactory() public {
        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.CanonicalFactoryHasNoCode.selector, nonAgent));
        new AgentswapPoolFactory(
            nonAgent,
            address(assetRegistry),
            address(quoteRegistry),
            address(venue),
            address(policyRegistry),
            address(feeTreasury),
            address(this)
        );
    }

    function testConstructorRejectsZeroRegistries() public {
        vm.expectRevert(AgentswapPoolFactory.ZeroRegistry.selector);
        new AgentswapPoolFactory(
            address(v3Factory),
            address(0),
            address(quoteRegistry),
            address(venue),
            address(policyRegistry),
            address(feeTreasury),
            address(this)
        );

        vm.expectRevert(AgentswapPoolFactory.ZeroRegistry.selector);
        new AgentswapPoolFactory(
            address(v3Factory),
            address(assetRegistry),
            address(0),
            address(venue),
            address(policyRegistry),
            address(feeTreasury),
            address(this)
        );

        vm.expectRevert(AgentswapPoolFactory.ZeroRegistry.selector);
        new AgentswapPoolFactory(
            address(v3Factory),
            address(assetRegistry),
            address(quoteRegistry),
            address(0),
            address(policyRegistry),
            address(feeTreasury),
            address(this)
        );

        vm.expectRevert(AgentswapPoolFactory.ZeroRegistry.selector);
        new AgentswapPoolFactory(
            address(v3Factory),
            address(assetRegistry),
            address(quoteRegistry),
            address(venue),
            address(0),
            address(feeTreasury),
            address(this)
        );
    }

    function testConstructorRejectsCodelessRegistries() public {
        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.RegistryHasNoCode.selector, nonAgent));
        new AgentswapPoolFactory(
            address(v3Factory),
            nonAgent,
            address(quoteRegistry),
            address(venue),
            address(policyRegistry),
            address(feeTreasury),
            address(this)
        );

        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.RegistryHasNoCode.selector, nonAgent));
        new AgentswapPoolFactory(
            address(v3Factory),
            address(assetRegistry),
            nonAgent,
            address(venue),
            address(policyRegistry),
            address(feeTreasury),
            address(this)
        );

        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.RegistryHasNoCode.selector, nonAgent));
        new AgentswapPoolFactory(
            address(v3Factory),
            address(assetRegistry),
            address(quoteRegistry),
            nonAgent,
            address(policyRegistry),
            address(feeTreasury),
            address(this)
        );

        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.RegistryHasNoCode.selector, nonAgent));
        new AgentswapPoolFactory(
            address(v3Factory),
            address(assetRegistry),
            address(quoteRegistry),
            address(venue),
            nonAgent,
            address(feeTreasury),
            address(this)
        );
    }

    function testConstructorRejectsZeroTreasury() public {
        vm.expectRevert(AgentswapPoolFactory.ZeroTreasury.selector);
        new AgentswapPoolFactory(
            address(v3Factory),
            address(assetRegistry),
            address(quoteRegistry),
            address(venue),
            address(policyRegistry),
            address(0),
            address(this)
        );
    }

    function testConstructorRejectsCodelessTreasury() public {
        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.TreasuryHasNoCode.selector, nonAgent));
        new AgentswapPoolFactory(
            address(v3Factory),
            address(assetRegistry),
            address(quoteRegistry),
            address(venue),
            address(policyRegistry),
            nonAgent,
            address(this)
        );
    }

    function testConstructorRejectsInactiveFeeRecipient() public {
        MockVenueAccount inactive = new MockVenueAccount();
        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.NotActiveFeeRecipient.selector, address(inactive)));
        new AgentswapPoolFactory(
            address(v3Factory),
            address(assetRegistry),
            address(quoteRegistry),
            address(venue),
            address(policyRegistry),
            address(inactive),
            address(this)
        );
    }

    function testConstructorRejectsRevokedFeeRecipient() public {
        MockVenueAccount revoked = new MockVenueAccount();
        venue.registerFacility(address(revoked), TREASURY);
        venue.revokeFacility(address(revoked));

        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.NotActiveFeeRecipient.selector, address(revoked)));
        new AgentswapPoolFactory(
            address(v3Factory),
            address(assetRegistry),
            address(quoteRegistry),
            address(venue),
            address(policyRegistry),
            address(revoked),
            address(this)
        );
    }

    function testGovernanceTwoStep() public {
        gatedFactory.transferGovernance(nonAgent);
        assertEq(gatedFactory.pendingGovernance(), nonAgent);

        vm.prank(nonAgent);
        gatedFactory.acceptGovernance();
        assertEq(gatedFactory.governance(), nonAgent);

        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, address(this)));
        gatedFactory.setTreasury(address(feeTreasury));
    }

    // ---------------------------------------------------------------------
    // createPool: allowed combinations
    // ---------------------------------------------------------------------

    function testCreatePoolGatedQuote() public {
        address expectedPool = _nextPoolAddress();
        (address token0, address token1) = _sorted(address(gated), address(quote));

        vm.expectEmit(true, true, true, true, address(gatedFactory));
        emit GatedPoolCreated(expectedPool, token0, token1, DEFAULT_FEE, DEFAULT_SQRT_PRICE);

        address poolAddress = gatedFactory.createPool(address(gated), address(quote), DEFAULT_FEE, DEFAULT_SQRT_PRICE);
        MockV3Pool pool = MockV3Pool(poolAddress);

        assertEq(poolAddress, expectedPool);
        assertEq(pool.token0(), token0);
        assertEq(pool.token1(), token1);
        assertEq(pool.fee(), DEFAULT_FEE);
        assertEq(pool.sqrtPriceX96(), DEFAULT_SQRT_PRICE);
        assertEq(pool.initializeCalls(), 1);
        assertEq(pool.feeProtocol0(), 8);
        assertEq(pool.feeProtocol1(), 8);
        assertEq(pool.setFeeProtocolCalls(), 1);

        assertEq(v3Factory.createPoolCalls(), 1);
        assertEq(v3Factory.getPool(token0, token1, DEFAULT_FEE), poolAddress);
        assertEq(v3Factory.getPool(token1, token0, DEFAULT_FEE), poolAddress);

        assertTrue(venue.isFacilityOfCategory(poolAddress, FacilityCategory.POOL));
        assertTrue(venue.isFacilityOfType(poolAddress, POOL));
        assertEq(venue.facilityType(poolAddress), POOL);
        assertEq(uint256(venue.facilityCategory(poolAddress)), uint256(FacilityCategory.POOL));
        assertEq(venue.factoryOf(poolAddress), address(gatedFactory));

        address[] memory gatedPools = assetRegistry.poolsOf(address(gated));
        assertEq(gatedPools.length, 1);
        assertEq(gatedPools[0], poolAddress);
        assertEq(assetRegistry.poolsOf(address(quote)).length, 0);
    }

    function testCreatePoolAcceptsReverseTokenOrder() public {
        address expectedPool = _nextPoolAddress();
        (address token0, address token1) = _sorted(address(gated), address(quote));

        vm.expectEmit(true, true, true, true, address(gatedFactory));
        emit GatedPoolCreated(expectedPool, token0, token1, DEFAULT_FEE, DEFAULT_SQRT_PRICE);

        address poolAddress = gatedFactory.createPool(address(quote), address(gated), DEFAULT_FEE, DEFAULT_SQRT_PRICE);

        assertEq(poolAddress, expectedPool);
        assertEq(MockV3Pool(poolAddress).token0(), token0);
        assertEq(MockV3Pool(poolAddress).token1(), token1);
    }

    function testCreatePoolBothGated() public {
        address expectedPool = _nextPoolAddress();
        (address token0, address token1) = _sorted(address(gated), address(gated2));

        vm.expectEmit(true, true, true, true, address(gatedFactory));
        emit GatedPoolCreated(expectedPool, token0, token1, DEFAULT_FEE, DEFAULT_SQRT_PRICE);

        address poolAddress = gatedFactory.createPool(address(gated2), address(gated), DEFAULT_FEE, DEFAULT_SQRT_PRICE);

        assertEq(poolAddress, expectedPool);
        assertEq(assetRegistry.poolsOf(address(gated)).length, 1);
        assertEq(assetRegistry.poolsOf(address(gated))[0], poolAddress);
        assertEq(assetRegistry.poolsOf(address(gated2)).length, 1);
        assertEq(assetRegistry.poolsOf(address(gated2))[0], poolAddress);
    }

    function testCreatePoolBothGatedDifferentCreatorsReverts() public {
        AgenticToken gated3 = AgenticToken(_createTokenFor(agent, agent2, 1_000 ether));

        // Neither creator can create a gated/gated pool that includes the other
        // creator's token: creator-only applies to every gated side.
        vm.expectRevert(
            abi.encodeWithSelector(AgentswapPoolFactory.NotAssetCreator.selector, address(gated3), address(this))
        );
        gatedFactory.createPool(address(gated), address(gated3), DEFAULT_FEE, DEFAULT_SQRT_PRICE);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.NotAssetCreator.selector, address(gated), agent));
        gatedFactory.createPool(address(gated), address(gated3), DEFAULT_FEE, DEFAULT_SQRT_PRICE);
    }

    function testNonCreatorCannotConsumePoolCap() public {
        uint24[4] memory fees = [uint24(500), uint24(3000), uint24(10000), uint24(500)];

        for (uint256 i; i < fees.length; ++i) {
            vm.prank(projectOwner);
            vm.expectRevert(
                abi.encodeWithSelector(AgentswapPoolFactory.NotAssetCreator.selector, address(gated), projectOwner)
            );
            gatedFactory.createPool(address(gated), address(quote), fees[i], DEFAULT_SQRT_PRICE);
        }

        // The creator's own pool still fits; no junk record consumed a slot.
        address poolAddress = gatedFactory.createPool(address(gated), address(quote), DEFAULT_FEE, DEFAULT_SQRT_PRICE);
        assertEq(assetRegistry.poolsOf(address(gated)).length, 1);
        assertEq(assetRegistry.poolsOf(address(gated))[0], poolAddress);
    }

    function testCreatePoolRejectsNonCreator() public {
        // Pool creation is creator-authorized; a non-agent project account that
        // did not create the gated token cannot consume the pool slots.
        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgentswapPoolFactory.NotAssetCreator.selector, address(gated), projectOwner)
        );
        gatedFactory.createPool(address(gated), address(quote), DEFAULT_FEE, DEFAULT_SQRT_PRICE);
    }

    function testCreatePoolAllFourFeeTiers() public {
        gatedFactory.enableFeeAmount(100, 1);

        uint24[4] memory fees = [uint24(100), uint24(500), uint24(3000), uint24(10000)];
        for (uint256 i; i < fees.length; ++i) {
            address poolAddress = gatedFactory.createPool(address(gated), address(quote), fees[i], DEFAULT_SQRT_PRICE);
            assertEq(MockV3Pool(poolAddress).fee(), fees[i]);
            assertEq(MockV3Pool(poolAddress).feeProtocol0(), 8);
            assertEq(MockV3Pool(poolAddress).feeProtocol1(), 8);
        }

        assertEq(v3Factory.createPoolCalls(), 4);
        assertEq(assetRegistry.poolsOf(address(gated)).length, 4);
    }

    function testCreatePoolAcceptsSqrtPriceBoundaries() public {
        MockV3Pool low = _createPool(address(gated), address(quote), 500, MIN_SQRT_RATIO);
        MockV3Pool high = _createPool(address(gated), address(quote), 3000, MAX_SQRT_RATIO - 1);

        assertEq(low.sqrtPriceX96(), MIN_SQRT_RATIO);
        assertEq(high.sqrtPriceX96(), MAX_SQRT_RATIO - 1);
        assertEq(low.feeProtocol0(), 8);
        assertEq(high.feeProtocol1(), 8);
    }

    // ---------------------------------------------------------------------
    // createPool: rejections
    // ---------------------------------------------------------------------

    function testCreatePoolRejectsZeroToken() public {
        vm.expectRevert(AgentswapPoolFactory.ZeroToken.selector);
        gatedFactory.createPool(address(0), address(quote), DEFAULT_FEE, DEFAULT_SQRT_PRICE);

        vm.expectRevert(AgentswapPoolFactory.ZeroToken.selector);
        gatedFactory.createPool(address(gated), address(0), DEFAULT_FEE, DEFAULT_SQRT_PRICE);
    }

    function testCreatePoolRejectsIdenticalTokens() public {
        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.IdenticalTokens.selector, address(gated)));
        gatedFactory.createPool(address(gated), address(gated), DEFAULT_FEE, DEFAULT_SQRT_PRICE);
    }

    function testCreatePoolRejectsDisallowedFee() public {
        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.FeeNotAllowed.selector, uint24(100)));
        gatedFactory.createPool(address(gated), address(quote), 100, DEFAULT_SQRT_PRICE);

        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.FeeNotAllowed.selector, uint24(12345)));
        gatedFactory.createPool(address(gated), address(quote), 12345, DEFAULT_SQRT_PRICE);
    }

    function testCreatePoolRejectsPublicPublic() public {
        vm.expectRevert(AgentswapPoolFactory.NoGatedAsset.selector);
        gatedFactory.createPool(address(quote), address(quote2), DEFAULT_FEE, DEFAULT_SQRT_PRICE);
    }

    function testCreatePoolRejectsNoGatedAsset() public {
        vm.expectRevert(AgentswapPoolFactory.NoGatedAsset.selector);
        gatedFactory.createPool(address(quote), nonAgent, DEFAULT_FEE, DEFAULT_SQRT_PRICE);
    }

    function testCreatePoolRejectsNonQuoteSide() public {
        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.NotQuoteAsset.selector, nonAgent));
        gatedFactory.createPool(address(gated), nonAgent, DEFAULT_FEE, DEFAULT_SQRT_PRICE);

        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.NotQuoteAsset.selector, nonAgent));
        gatedFactory.createPool(nonAgent, address(gated), DEFAULT_FEE, DEFAULT_SQRT_PRICE);
    }

    function testCreatePoolRejectsInvalidSqrtPrice() public {
        uint160[4] memory invalid = [uint160(0), MIN_SQRT_RATIO - 1, MAX_SQRT_RATIO, type(uint160).max];

        for (uint256 i; i < invalid.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.InvalidSqrtPrice.selector, invalid[i]));
            gatedFactory.createPool(address(gated), address(quote), DEFAULT_FEE, invalid[i]);
        }

        assertEq(v3Factory.createPoolCalls(), 0);
    }

    function testCreatePoolRequiresCanonicalFactoryOwnership() public {
        vm.prank(address(gatedFactory));
        v3Factory.setOwner(nonAgent);

        vm.expectRevert(
            abi.encodeWithSelector(
                AgentswapPoolFactory.NotCanonicalFactoryOwner.selector, nonAgent, address(gatedFactory)
            )
        );
        gatedFactory.createPool(address(gated), address(quote), DEFAULT_FEE, DEFAULT_SQRT_PRICE);

        assertEq(v3Factory.createPoolCalls(), 0);
        assertEq(v3Factory.getPool(address(gated), address(quote), DEFAULT_FEE), address(0));
    }

    function testCreatePoolRequiresPoolRegistrar() public {
        venue.setRegistrar(address(gatedFactory), FacilityCategory.POOL, false);
        address expectedPool = _nextPoolAddress();

        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticVenueRegistry.NotRegistrar.selector, address(gatedFactory), FacilityCategory.POOL
            )
        );
        gatedFactory.createPool(address(gated), address(quote), DEFAULT_FEE, DEFAULT_SQRT_PRICE);

        // Atomic revert: the canonical pool creation was rolled back too.
        assertEq(v3Factory.getPool(address(gated), address(quote), DEFAULT_FEE), address(0));
        assertFalse(venue.isFacilityOfCategory(expectedPool, FacilityCategory.POOL));
        assertEq(assetRegistry.poolsOf(address(gated)).length, 0);
    }

    function testCreatePoolRejectsDuplicatePool() public {
        address firstPool = gatedFactory.createPool(address(gated), address(quote), DEFAULT_FEE, DEFAULT_SQRT_PRICE);
        (address token0, address token1) = _sorted(address(gated), address(quote));

        vm.expectRevert(abi.encodeWithSelector(MockV3Factory.PoolAlreadyExists.selector, token0, token1, DEFAULT_FEE));
        gatedFactory.createPool(address(gated), address(quote), DEFAULT_FEE, DEFAULT_SQRT_PRICE);

        address[] memory pools = assetRegistry.poolsOf(address(gated));
        assertEq(pools.length, 1);
        assertEq(pools[0], firstPool);
    }

    // ---------------------------------------------------------------------
    // setProtocolFee
    // ---------------------------------------------------------------------

    function testSetProtocolFee() public {
        MockV3Pool pool = _createPool(address(gated), address(quote));

        vm.expectEmit(true, false, false, true, address(gatedFactory));
        emit ProtocolFeeSet(address(pool), 4, 10);
        gatedFactory.setProtocolFee(address(pool), 4, 10);

        assertEq(pool.feeProtocol0(), 4);
        assertEq(pool.feeProtocol1(), 10);
        assertEq(pool.setFeeProtocolCalls(), 2);

        gatedFactory.setProtocolFee(address(pool), 0, 0);
        assertEq(pool.feeProtocol0(), 0);
        assertEq(pool.feeProtocol1(), 0);
        assertEq(pool.setFeeProtocolCalls(), 3);
    }

    function testSetProtocolFeeOnlyGovernance() public {
        MockV3Pool pool = _createPool(address(gated), address(quote));

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonAgent));
        gatedFactory.setProtocolFee(address(pool), 8, 8);

        assertEq(pool.feeProtocol0(), 8);
        assertEq(pool.feeProtocol1(), 8);
    }

    function testSetProtocolFeeRejectsInvalidPool() public {
        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.InvalidPool.selector, address(0)));
        gatedFactory.setProtocolFee(address(0), 8, 8);
    }

    function testSetProtocolFeeRejectsOutOfRange() public {
        MockV3Pool pool = _createPool(address(gated), address(quote));

        uint8[5] memory invalid = [uint8(1), uint8(3), uint8(11), uint8(12), uint8(255)];
        for (uint256 i; i < invalid.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.InvalidProtocolFee.selector, invalid[i]));
            gatedFactory.setProtocolFee(address(pool), invalid[i], 8);
        }

        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.InvalidProtocolFee.selector, uint8(3)));
        gatedFactory.setProtocolFee(address(pool), 8, 3);

        assertEq(pool.feeProtocol0(), 8);
        assertEq(pool.feeProtocol1(), 8);
    }

    // ---------------------------------------------------------------------
    // collectProtocol
    // ---------------------------------------------------------------------

    function testCollectProtocolPaysTreasury() public {
        MockV3Pool pool = _createPool(address(gated), address(quote));
        pool.setProtocolFees(1_000, 2_000);

        vm.expectEmit(true, true, false, true, address(gatedFactory));
        emit ProtocolCollected(address(pool), address(feeTreasury), 600, 2_000);

        (uint128 amount0, uint128 amount1) = gatedFactory.collectProtocol(address(pool), 600, 2_500);

        assertEq(amount0, 600);
        assertEq(amount1, 2_000);
        assertEq(pool.collectRecipient(), address(feeTreasury));
        assertEq(pool.collectAmount0Requested(), 600);
        assertEq(pool.collectAmount1Requested(), 2_500);
        assertEq(pool.collectProtocolCalls(), 1);
        assertEq(pool.protocolFees0(), 400);
        assertEq(pool.protocolFees1(), 0);
    }

    function testCollectProtocolUsesCurrentTreasury() public {
        MockV3Pool pool = _createPool(address(gated), address(quote));
        pool.setProtocolFees(100, 100);
        gatedFactory.setTreasury(address(feeTreasury2));

        (uint128 amount0, uint128 amount1) = gatedFactory.collectProtocol(address(pool), 100, 100);

        assertEq(amount0, 100);
        assertEq(amount1, 100);
        assertEq(pool.collectRecipient(), address(feeTreasury2));
    }

    function testCollectProtocolZeroRequests() public {
        MockV3Pool pool = _createPool(address(gated), address(quote));
        pool.setProtocolFees(1_000, 2_000);

        vm.expectEmit(true, true, false, true, address(gatedFactory));
        emit ProtocolCollected(address(pool), address(feeTreasury), 0, 0);
        (uint128 amount0, uint128 amount1) = gatedFactory.collectProtocol(address(pool), 0, 0);

        assertEq(amount0, 0);
        assertEq(amount1, 0);
        assertEq(pool.protocolFees0(), 1_000);
        assertEq(pool.protocolFees1(), 2_000);
    }

    function testCollectProtocolRejectsInvalidPool() public {
        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.InvalidPool.selector, address(0)));
        gatedFactory.collectProtocol(address(0), 1, 1);
    }

    function testCollectProtocolOnlyGovernance() public {
        MockV3Pool pool = _createPool(address(gated), address(quote));

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonAgent));
        gatedFactory.collectProtocol(address(pool), 1, 1);
    }

    function testCollectProtocolRecipientIsAlwaysTreasury() public {
        MockV3Pool pool = _createPool(address(gated), address(quote));
        pool.setProtocolFees(1_000, 1_000);

        // Even a new governance account cannot choose a recipient.
        gatedFactory.transferGovernance(nonAgent);
        vm.prank(nonAgent);
        gatedFactory.acceptGovernance();

        vm.prank(nonAgent);
        gatedFactory.collectProtocol(address(pool), 500, 500);

        assertEq(pool.collectRecipient(), address(feeTreasury));
    }

    // ---------------------------------------------------------------------
    // setTreasury
    // ---------------------------------------------------------------------

    function testSetTreasury() public {
        vm.expectEmit(true, false, false, true, address(gatedFactory));
        emit TreasurySet(address(feeTreasury2));
        gatedFactory.setTreasury(address(feeTreasury2));

        assertEq(gatedFactory.treasury(), address(feeTreasury2));
    }

    function testSetTreasuryOnlyGovernance() public {
        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonAgent));
        gatedFactory.setTreasury(address(feeTreasury2));

        assertEq(gatedFactory.treasury(), address(feeTreasury));
    }

    function testSetTreasuryRejectsZero() public {
        vm.expectRevert(AgentswapPoolFactory.ZeroTreasury.selector);
        gatedFactory.setTreasury(address(0));
    }

    function testSetTreasuryRejectsInactiveFeeRecipient() public {
        MockVenueAccount inactive = new MockVenueAccount();

        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.NotActiveFeeRecipient.selector, address(inactive)));
        gatedFactory.setTreasury(address(inactive));
    }

    function testSetTreasuryRejectsRevokedFeeRecipient() public {
        MockVenueAccount revoked = new MockVenueAccount();
        venue.registerFacility(address(revoked), TREASURY);
        venue.revokeFacility(address(revoked));

        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.NotActiveFeeRecipient.selector, address(revoked)));
        gatedFactory.setTreasury(address(revoked));
    }

    function testSetTreasuryRejectsWrongCategory() public {
        MockVenueAccount lpManager = new MockVenueAccount();
        venue.registerFacility(address(lpManager), NPM);

        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.NotActiveFeeRecipient.selector, address(lpManager)));
        gatedFactory.setTreasury(address(lpManager));
    }

    // ---------------------------------------------------------------------
    // enableFeeAmount / isAllowedFee
    // ---------------------------------------------------------------------

    function testIsAllowedFee() public view {
        assertTrue(gatedFactory.isAllowedFee(500));
        assertTrue(gatedFactory.isAllowedFee(3000));
        assertTrue(gatedFactory.isAllowedFee(10000));
        assertFalse(gatedFactory.isAllowedFee(100));
        assertFalse(gatedFactory.isAllowedFee(0));
        assertFalse(gatedFactory.isAllowedFee(12345));
    }

    function testEnableFeeAmount() public {
        uint256 callsBefore = v3Factory.enableFeeAmountCalls();
        assertFalse(gatedFactory.isAllowedFee(100));

        vm.expectEmit(false, false, false, true, address(gatedFactory));
        emit FeeAmountEnabled(100, 1);
        gatedFactory.enableFeeAmount(100, 1);

        assertTrue(gatedFactory.isAllowedFee(100));
        assertEq(v3Factory.feeAmountTickSpacing(100), 1);
        assertEq(v3Factory.enableFeeAmountCalls(), callsBefore + 1);
    }

    function testEnableFeeAmountAllowsNewPoolTier() public {
        gatedFactory.enableFeeAmount(100, 1);
        MockV3Pool pool = _createPool(address(gated), address(quote), 100, DEFAULT_SQRT_PRICE);
        assertEq(pool.fee(), 100);
    }

    function testEnableFeeAmountOnlyGovernance() public {
        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonAgent));
        gatedFactory.enableFeeAmount(100, 1);

        assertFalse(gatedFactory.isAllowedFee(100));
    }

    function testEnableFeeAmountRequiresCanonicalFactoryOwnership() public {
        vm.prank(address(gatedFactory));
        v3Factory.setOwner(nonAgent);

        vm.expectRevert(
            abi.encodeWithSelector(
                AgentswapPoolFactory.NotCanonicalFactoryOwner.selector, nonAgent, address(gatedFactory)
            )
        );
        gatedFactory.enableFeeAmount(100, 1);

        assertFalse(gatedFactory.isAllowedFee(100));
    }

    function testEnableFeeAmountPassesCanonicalValidation() public {
        vm.expectRevert(abi.encodeWithSelector(MockV3Factory.FeeAlreadyEnabled.selector, uint24(500)));
        gatedFactory.enableFeeAmount(500, 10);

        vm.expectRevert(abi.encodeWithSelector(MockV3Factory.FeeTooLarge.selector, uint24(1_000_000)));
        gatedFactory.enableFeeAmount(1_000_000, 1);

        vm.expectRevert(abi.encodeWithSelector(MockV3Factory.InvalidTickSpacing.selector, int24(0)));
        gatedFactory.enableFeeAmount(100, 0);
    }

    // ---------------------------------------------------------------------
    // transferCanonicalFactoryOwnership
    // ---------------------------------------------------------------------

    function testTransferCanonicalFactoryOwnership() public {
        uint256 callsBefore = v3Factory.setOwnerCalls();

        vm.expectEmit(true, false, false, true, address(gatedFactory));
        emit CanonicalFactoryOwnerChanged(nonAgent);
        gatedFactory.transferCanonicalFactoryOwnership(nonAgent);

        assertEq(v3Factory.owner(), nonAgent);
        assertEq(v3Factory.setOwnerCalls(), callsBefore + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                AgentswapPoolFactory.NotCanonicalFactoryOwner.selector, nonAgent, address(gatedFactory)
            )
        );
        gatedFactory.createPool(address(gated), address(quote), DEFAULT_FEE, DEFAULT_SQRT_PRICE);
    }

    function testTransferCanonicalFactoryOwnershipOnlyGovernance() public {
        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonAgent));
        gatedFactory.transferCanonicalFactoryOwnership(nonAgent);

        assertEq(v3Factory.owner(), address(gatedFactory));
    }

    function testTransferCanonicalFactoryOwnershipRejectsZero() public {
        vm.expectRevert(AgentswapPoolFactory.ZeroNewOwner.selector);
        gatedFactory.transferCanonicalFactoryOwnership(address(0));

        assertEq(v3Factory.owner(), address(gatedFactory));
    }

    function testTransferCanonicalFactoryOwnershipRequiresCurrentOwnership() public {
        vm.prank(address(gatedFactory));
        v3Factory.setOwner(nonAgent);

        vm.expectRevert(
            abi.encodeWithSelector(
                AgentswapPoolFactory.NotCanonicalFactoryOwner.selector, nonAgent, address(gatedFactory)
            )
        );
        gatedFactory.transferCanonicalFactoryOwnership(address(this));
    }

    // ---------------------------------------------------------------------
    // Fuzz
    // ---------------------------------------------------------------------

    function testFuzzCreatePoolAllowedFeeTier(uint24 feeSeed) public {
        uint24[3] memory fees = [uint24(500), uint24(3000), uint24(10000)];
        uint24 fee = fees[feeSeed % 3];

        MockV3Pool pool = _createPool(address(gated), address(quote), fee, DEFAULT_SQRT_PRICE);

        assertEq(pool.fee(), fee);
        assertEq(pool.feeProtocol0(), 8);
        assertEq(pool.feeProtocol1(), 8);
        assertTrue(venue.isFacilityOfCategory(address(pool), FacilityCategory.POOL));
        assertEq(assetRegistry.poolsOf(address(gated)).length, 1);
    }

    function testFuzzCreatePoolValidSqrtPrice(uint160 sqrtSeed) public {
        uint160 sqrtPriceX96 = uint160(bound(uint256(sqrtSeed), MIN_SQRT_RATIO, uint256(MAX_SQRT_RATIO) - 1));

        MockV3Pool pool = _createPool(address(gated), address(quote), DEFAULT_FEE, sqrtPriceX96);

        assertEq(pool.sqrtPriceX96(), sqrtPriceX96);
        assertEq(pool.initializeCalls(), 1);
    }

    function testFuzzCreatePoolRejectsOutOfRangeSqrtPrice(uint160 sqrtSeed, bool aboveMax) public {
        uint160 sqrtPriceX96;
        if (aboveMax) {
            sqrtPriceX96 = uint160(bound(uint256(sqrtSeed), MAX_SQRT_RATIO, type(uint160).max));
        } else {
            sqrtPriceX96 = uint160(bound(uint256(sqrtSeed), 0, MIN_SQRT_RATIO - 1));
        }

        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.InvalidSqrtPrice.selector, sqrtPriceX96));
        gatedFactory.createPool(address(gated), address(quote), DEFAULT_FEE, sqrtPriceX96);
    }

    function testFuzzNonQuoteTokenRejected(address other) public {
        vm.assume(
            other != address(0) && other != address(gated) && other != address(gated2) && other != address(quote)
                && other != address(quote2)
        );

        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.NotQuoteAsset.selector, other));
        gatedFactory.createPool(address(gated), other, DEFAULT_FEE, DEFAULT_SQRT_PRICE);
    }

    function testFuzzTokenOrderBothGated(bool reverse) public {
        (address tokenA, address tokenB) =
            reverse ? (address(gated2), address(gated)) : (address(gated), address(gated2));
        (address token0, address token1) = _sorted(address(gated), address(gated2));
        address expectedPool = _nextPoolAddress();

        vm.expectEmit(true, true, true, true, address(gatedFactory));
        emit GatedPoolCreated(expectedPool, token0, token1, DEFAULT_FEE, DEFAULT_SQRT_PRICE);

        address poolAddress = gatedFactory.createPool(tokenA, tokenB, DEFAULT_FEE, DEFAULT_SQRT_PRICE);

        assertEq(poolAddress, expectedPool);
        assertEq(MockV3Pool(poolAddress).token0(), token0);
        assertEq(MockV3Pool(poolAddress).token1(), token1);
        assertEq(assetRegistry.poolsOf(address(gated)).length, 1);
        assertEq(assetRegistry.poolsOf(address(gated2)).length, 1);
    }

    function testFuzzDisallowedFeeRejected(uint24 fee) public {
        vm.assume(fee != 500 && fee != 3000 && fee != 10000);

        vm.expectRevert(abi.encodeWithSelector(AgentswapPoolFactory.FeeNotAllowed.selector, fee));
        gatedFactory.createPool(address(gated), address(quote), fee, DEFAULT_SQRT_PRICE);
    }
}
