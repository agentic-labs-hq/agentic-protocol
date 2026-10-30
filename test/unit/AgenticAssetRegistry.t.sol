// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {Governance2Step} from "../../contracts/common/Governance2Step.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";
import {AgenticAssetRegistry} from "../../contracts/registry/AgenticAssetRegistry.sol";
import {AssetType, FacilityCategory} from "../../contracts/common/Types.sol";

import {MockAgentAsset} from "../mocks/MockAgentAsset.sol";
import {MockGatedPool} from "../mocks/MockGatedPool.sol";
import {MockPolicy} from "../mocks/MockPolicy.sol";
import {TokenAssetFixture} from "../helpers/TokenAssetFixture.sol";

contract AgenticAssetRegistryTest is TokenAssetFixture {
    event AssetRegistered(address indexed asset, address indexed policy, address indexed creator);
    event PoolRecorded(address indexed asset, address indexed pool);
    event RegistrarSet(address indexed account, bool enabled);

    address internal constant QUOTE = address(0xBEEF);

    function setUp() public {
        _deployTokenAsset();
    }

    // ---------------------------------------------------------------------
    // Construction and configuration
    // ---------------------------------------------------------------------

    function testInitialState() public view {
        assertEq(assetRegistry.governance(), address(this));
        assertEq(assetRegistry.pendingGovernance(), address(0));
        assertEq(assetRegistry.policyRegistry(), address(policyRegistry));
        assertEq(assetRegistry.venueRegistry(), address(venue));
        assertEq(assetRegistry.maxPoolsPerAsset(), MAX_POOLS);
        assertFalse(assetRegistry.isRegistrar(address(assetRegistrar)));
    }

    function testConstructorRejectsZeroGovernance() public {
        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        new AgenticAssetRegistry(address(0), address(policyRegistry), address(venue), MAX_POOLS);
    }

    function testConstructorRejectsZeroRegistries() public {
        vm.expectRevert(AgenticAssetRegistry.ZeroRegistry.selector);
        new AgenticAssetRegistry(address(this), address(0), address(venue), MAX_POOLS);

        vm.expectRevert(AgenticAssetRegistry.ZeroRegistry.selector);
        new AgenticAssetRegistry(address(this), address(policyRegistry), address(0), MAX_POOLS);
    }

    function testConstructorRejectsCodelessRegistries() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticAssetRegistry.RegistryHasNoCode.selector, nonAgent));
        new AgenticAssetRegistry(address(this), nonAgent, address(venue), MAX_POOLS);

        vm.expectRevert(abi.encodeWithSelector(AgenticAssetRegistry.RegistryHasNoCode.selector, nonAgent));
        new AgenticAssetRegistry(address(this), address(policyRegistry), nonAgent, MAX_POOLS);
    }

    function testConstructorRejectsZeroPoolCap() public {
        vm.expectRevert(AgenticAssetRegistry.InvalidMaxPools.selector);
        new AgenticAssetRegistry(address(this), address(policyRegistry), address(venue), 0);
    }

    function testSetRegistrar() public {
        vm.expectEmit(true, false, false, true, address(assetRegistry));
        emit RegistrarSet(address(assetRegistrar), true);
        assetRegistry.setRegistrar(address(assetRegistrar), true);
        assertTrue(assetRegistry.isRegistrar(address(assetRegistrar)));

        vm.expectEmit(true, false, false, true, address(assetRegistry));
        emit RegistrarSet(address(assetRegistrar), false);
        assetRegistry.setRegistrar(address(assetRegistrar), false);
        assertFalse(assetRegistry.isRegistrar(address(assetRegistrar)));
    }

    function testSetRegistrarOnlyGovernance() public {
        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonAgent));
        assetRegistry.setRegistrar(address(assetRegistrar), true);
    }

    function testSetRegistrarRejectsZero() public {
        vm.expectRevert(AgenticAssetRegistry.ZeroRegistrar.selector);
        assetRegistry.setRegistrar(address(0), true);
    }

    function testSetRegistrarRejectsCodeless() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticAssetRegistry.RegistrarHasNoCode.selector, nonAgent));
        assetRegistry.setRegistrar(nonAgent, true);
    }

    function testDisabledRegistrarRejected() public {
        assetRegistry.setRegistrar(address(assetRegistrar), true);
        assetRegistry.setRegistrar(address(assetRegistrar), false);

        vm.expectRevert(abi.encodeWithSelector(AgenticAssetRegistry.NotRegistrar.selector, address(assetRegistrar)));
        assetRegistrar.register(address(assetRegistry), address(0), address(policy), agent);
    }

    function testGovernanceTwoStep() public {
        address newGov = address(0xC0FFEE);
        assetRegistry.transferGovernance(newGov);
        assertEq(assetRegistry.pendingGovernance(), newGov);

        vm.prank(newGov);
        assetRegistry.acceptGovernance();
        assertEq(assetRegistry.governance(), newGov);

        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, address(this)));
        assetRegistry.setRegistrar(address(assetRegistrar), true);
    }

    // ---------------------------------------------------------------------
    // Asset registration authorization and stamps
    // ---------------------------------------------------------------------

    function testFactoryCreatedAssetIsRegistered() public {
        AgenticToken token = _createRegisteredToken();

        assertTrue(assetRegistry.isRegistered(address(token)));
        assertEq(assetRegistry.policyOf(address(token)), address(policy));
        assertEq(assetRegistry.creatorOf(address(token)), agent);
    }

    function testAssetRegisteredEvent() public {
        vm.recordLogs();
        AgenticToken token = _createRegisteredToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 topic = keccak256("AssetRegistered(address,address,address)");
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(assetRegistry) || logs[i].topics[0] != topic) continue;
            assertEq(address(uint160(uint256(logs[i].topics[1]))), address(token));
            assertEq(address(uint160(uint256(logs[i].topics[2]))), address(policy));
            assertEq(address(uint160(uint256(logs[i].topics[3]))), agent);
            found = true;
        }
        assertTrue(found);
    }

    function testRandomCallerIsNotRegistrar() public {
        AgenticToken token = _createRegisteredToken();

        vm.expectRevert(abi.encodeWithSelector(AgenticAssetRegistry.NotRegistrar.selector, address(this)));
        assetRegistry.registerAsset(address(token), address(policy), agent);
    }

    function testOnlyFactoryStampAccepted() public {
        // Directly deployed token: its factory stamp is this test contract, not
        // the generic registrar that tries to register it.
        AgenticToken token = new AgenticToken(
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            address(this),
            address(policy),
            agent,
            _singleAddress(agent),
            _singleAmount(1 ether),
            DEFAULT_URI
        );
        assetRegistry.setRegistrar(address(assetRegistrar), true);

        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticAssetRegistry.FactoryMismatch.selector, address(token), address(assetRegistrar), address(this)
            )
        );
        assetRegistrar.register(address(assetRegistry), address(token), address(policy), agent);
    }

    function testZeroAssetRejected() public {
        assetRegistry.setRegistrar(address(assetRegistrar), true);

        vm.expectRevert(AgenticAssetRegistry.ZeroAsset.selector);
        assetRegistrar.register(address(assetRegistry), address(0), address(policy), agent);
    }

    function testCodelessAssetRejected() public {
        assetRegistry.setRegistrar(address(assetRegistrar), true);

        vm.expectRevert(abi.encodeWithSelector(AgenticAssetRegistry.AssetHasNoCode.selector, nonAgent));
        assetRegistrar.register(address(assetRegistry), nonAgent, address(policy), agent);
    }

    function testPolicyMismatchRejected() public {
        MockAgentAsset asset = _newMockAsset(address(policy), agent, AssetType.FT);
        assetRegistry.setRegistrar(address(asset), true);

        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticAssetRegistry.PolicyMismatch.selector, address(asset), address(0xDEAD), address(policy)
            )
        );
        asset.registerOn(address(assetRegistry), address(0xDEAD), agent);
    }

    function testPolicyNotAllowedRejected() public {
        MockPolicy unknown = new MockPolicy(7);
        MockAgentAsset asset = _newMockAsset(address(unknown), agent, AssetType.FT);
        assetRegistry.setRegistrar(address(asset), true);

        vm.expectRevert(abi.encodeWithSelector(AgenticAssetRegistry.PolicyNotAllowed.selector, address(unknown)));
        asset.registerOn(address(assetRegistry), address(unknown), agent);
    }

    function testCreatorMismatchRejected() public {
        MockAgentAsset asset = _newMockAsset(address(policy), agent, AssetType.FT);
        assetRegistry.setRegistrar(address(asset), true);

        vm.expectRevert(
            abi.encodeWithSelector(AgenticAssetRegistry.CreatorMismatch.selector, address(asset), agent2, agent)
        );
        asset.registerOn(address(assetRegistry), address(policy), agent2);
    }

    function testNonFTAssetRejected() public {
        MockAgentAsset asset = _newMockAsset(address(policy), agent, AssetType.NFT);
        assetRegistry.setRegistrar(address(asset), true);

        vm.expectRevert(
            abi.encodeWithSelector(AgenticAssetRegistry.AssetTypeNotSupported.selector, address(asset), AssetType.NFT)
        );
        asset.registerOn(address(assetRegistry), address(policy), agent);
    }

    function testMockAssetRegistrationRecordsStamps() public {
        MockAgentAsset asset = _newMockAsset(address(policy), agent, AssetType.FT);
        assetRegistry.setRegistrar(address(asset), true);

        vm.expectEmit(true, true, true, true, address(assetRegistry));
        emit AssetRegistered(address(asset), address(policy), agent);
        asset.registerOn(address(assetRegistry), address(policy), agent);

        assertTrue(assetRegistry.isRegistered(address(asset)));
        assertEq(assetRegistry.policyOf(address(asset)), address(policy));
        assertEq(assetRegistry.creatorOf(address(asset)), agent);
    }

    function testDuplicateAssetRejected() public {
        MockAgentAsset asset = _newMockAsset(address(policy), agent, AssetType.FT);
        assetRegistry.setRegistrar(address(asset), true);
        asset.registerOn(address(assetRegistry), address(policy), agent);

        vm.expectRevert(abi.encodeWithSelector(AgenticAssetRegistry.AssetAlreadyRegistered.selector, address(asset)));
        asset.registerOn(address(assetRegistry), address(policy), agent);
    }

    // ---------------------------------------------------------------------
    // Pool records
    // ---------------------------------------------------------------------

    function testRecordPoolWithAssetAsToken0() public {
        AgenticToken token = _createRegisteredToken();
        MockGatedPool pool = _deployActivePool(address(token), QUOTE);
        assetRegistry.setRegistrar(address(assetRegistrar), true);
        venue.setRegistrar(address(assetRegistrar), FacilityCategory.POOL, true);

        vm.expectEmit(true, true, false, true, address(assetRegistry));
        emit PoolRecorded(address(token), address(pool));
        assetRegistrar.record(address(assetRegistry), address(token), address(pool));

        address[] memory pools = assetRegistry.poolsOf(address(token));
        assertEq(pools.length, 1);
        assertEq(pools[0], address(pool));
    }

    function testRecordPoolWithAssetAsToken1() public {
        AgenticToken token = _createRegisteredToken();
        MockGatedPool pool = _deployActivePool(QUOTE, address(token));
        assetRegistry.setRegistrar(address(assetRegistrar), true);
        venue.setRegistrar(address(assetRegistrar), FacilityCategory.POOL, true);

        assetRegistrar.record(address(assetRegistry), address(token), address(pool));
        assertEq(assetRegistry.poolsOf(address(token)).length, 1);
    }

    function testRecordPoolRequiresPoolRegistrar() public {
        AgenticToken token = _createRegisteredToken();
        MockGatedPool pool = _deployActivePool(address(token), QUOTE);
        assetRegistry.setRegistrar(address(assetRegistrar), true);

        vm.expectRevert(abi.encodeWithSelector(AgenticAssetRegistry.NotPoolRegistrar.selector, address(assetRegistrar)));
        assetRegistrar.record(address(assetRegistry), address(token), address(pool));

        // This test contract is the fixture's POOL registrar; a random EOA is not.
        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticAssetRegistry.NotPoolRegistrar.selector, nonAgent));
        assetRegistry.recordPool(address(token), address(pool));
    }

    function testRecordPoolRequiresPoolCategoryRegistrar() public {
        AgenticToken token = _createRegisteredToken();
        MockGatedPool pool = _deployActivePool(address(token), QUOTE);
        // Being a registrar for another category does not grant POOL rights.
        venue.setRegistrar(address(assetRegistrar), FacilityCategory.LP_MANAGER, true);

        vm.expectRevert(abi.encodeWithSelector(AgenticAssetRegistry.NotPoolRegistrar.selector, address(assetRegistrar)));
        assetRegistrar.record(address(assetRegistry), address(token), address(pool));
    }

    function testRecordPoolRequiresRegisteredAsset() public {
        MockAgentAsset asset = _newMockAsset(address(policy), agent, AssetType.FT);
        MockGatedPool pool = _deployActivePool(address(asset), QUOTE);
        venue.setRegistrar(address(assetRegistrar), FacilityCategory.POOL, true);

        vm.expectRevert(abi.encodeWithSelector(AgenticAssetRegistry.AssetNotRegistered.selector, address(asset)));
        assetRegistrar.record(address(assetRegistry), address(asset), address(pool));
    }

    function testRecordPoolRejectsZeroPool() public {
        AgenticToken token = _createRegisteredToken();
        venue.setRegistrar(address(assetRegistrar), FacilityCategory.POOL, true);

        vm.expectRevert(AgenticAssetRegistry.ZeroPool.selector);
        assetRegistrar.record(address(assetRegistry), address(token), address(0));
    }

    function testRecordPoolRejectsInactivePool() public {
        AgenticToken token = _createRegisteredToken();
        MockGatedPool pool = new MockGatedPool(address(token), QUOTE);
        venue.setRegistrar(address(assetRegistrar), FacilityCategory.POOL, true);

        vm.expectRevert(abi.encodeWithSelector(AgenticAssetRegistry.PoolNotActive.selector, address(pool)));
        assetRegistrar.record(address(assetRegistry), address(token), address(pool));
    }

    function testRecordPoolRejectsMissingAsset() public {
        AgenticToken token = _createRegisteredToken();
        MockGatedPool pool = _deployActivePool(address(0x1111), address(0x2222));
        venue.setRegistrar(address(assetRegistrar), FacilityCategory.POOL, true);

        vm.expectRevert(
            abi.encodeWithSelector(AgenticAssetRegistry.PoolMissingAsset.selector, address(pool), address(token))
        );
        assetRegistrar.record(address(assetRegistry), address(token), address(pool));
    }

    function testRecordPoolDuplicateRejected() public {
        AgenticToken token = _createRegisteredToken();
        MockGatedPool pool = _deployActivePool(address(token), QUOTE);
        venue.setRegistrar(address(assetRegistrar), FacilityCategory.POOL, true);
        assetRegistrar.record(address(assetRegistry), address(token), address(pool));

        vm.expectRevert(
            abi.encodeWithSelector(AgenticAssetRegistry.PoolAlreadyRecorded.selector, address(token), address(pool))
        );
        assetRegistrar.record(address(assetRegistry), address(token), address(pool));
    }

    function testRecordPoolCapEnforced() public {
        AgenticToken token = _createRegisteredToken();
        venue.setRegistrar(address(assetRegistrar), FacilityCategory.POOL, true);

        for (uint256 i; i < MAX_POOLS; ++i) {
            MockGatedPool pool = _deployActivePool(address(token), address(uint160(0x5000 + i)));
            assetRegistrar.record(address(assetRegistry), address(token), address(pool));
        }
        assertEq(assetRegistry.poolsOf(address(token)).length, MAX_POOLS);

        MockGatedPool extra = _deployActivePool(address(token), address(0x6000));
        vm.expectRevert(abi.encodeWithSelector(AgenticAssetRegistry.PoolCapReached.selector, MAX_POOLS));
        assetRegistrar.record(address(assetRegistry), address(token), address(extra));
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _newMockAsset(address policy_, address creator_, AssetType assetType_)
        internal
        returns (MockAgentAsset asset)
    {
        asset = new MockAgentAsset(address(0), policy_, creator_, assetType_);
    }

    function _deployActivePool(address token0, address token1) internal returns (MockGatedPool pool) {
        pool = new MockGatedPool(token0, token1);
        _registerPool(pool);
    }

    function _singleAddress(address value) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = value;
    }

    function _singleAmount(uint256 value) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = value;
    }
}
