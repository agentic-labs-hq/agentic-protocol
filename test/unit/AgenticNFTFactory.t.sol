// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {AgenticPolicy} from "../../contracts/policy/AgenticPolicy.sol";
import {AgenticNFT} from "../../contracts/token/AgenticNFT.sol";
import {AgenticNFTFactory} from "../../contracts/token/AgenticNFTFactory.sol";
import {AgenticNFTRegistry} from "../../contracts/registry/AgenticNFTRegistry.sol";
import {AgenticPolicyRegistry} from "../../contracts/policy/AgenticPolicyRegistry.sol";
import {IAgentNFT, INFTMetadataResolver} from "../../contracts/interfaces/IAgentNFT.sol";
import {IAgentNFTFactory} from "../../contracts/interfaces/IAgentNFTFactory.sol";
import {AssetType} from "../../contracts/common/Types.sol";
import {MockPolicy} from "../mocks/MockPolicy.sol";
import {NFTAssetFixture} from "../helpers/NFTAssetFixture.sol";

/// @notice Minimal on-chain metadata resolver used to exercise the code check.
contract MockNFTMetadataResolver is INFTMetadataResolver {
    function tokenURI(address, uint256) external pure override returns (string memory) {
        return "mock://nft-metadata";
    }
}

contract AgenticNFTFactoryTest is NFTAssetFixture {
    function setUp() public {
        _deployNFTAsset();
    }

    // ---------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------

    function testConstructorStamps() public view {
        assertEq(nftFactory.policyRegistry(), address(policyRegistry));
        assertEq(nftFactory.assetRegistry(), address(nftRegistry));
    }

    function testConstructorRejectsZeroRegistries() public {
        vm.expectRevert(AgenticNFTFactory.ZeroRegistry.selector);
        new AgenticNFTFactory(address(0), address(nftRegistry));

        vm.expectRevert(AgenticNFTFactory.ZeroRegistry.selector);
        new AgenticNFTFactory(address(policyRegistry), address(0));
    }

    function testConstructorRejectsCodelessRegistries() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFactory.RegistryHasNoCode.selector, nonAgent));
        new AgenticNFTFactory(nonAgent, address(nftRegistry));

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFactory.RegistryHasNoCode.selector, nonAgent));
        new AgenticNFTFactory(address(policyRegistry), nonAgent);
    }

    // ---------------------------------------------------------------------
    // Permissionless creation and registry stamps
    // ---------------------------------------------------------------------

    function testCreateCollectionStamps() public {
        AgenticNFT nft = _createCollection(agent, address(0), DEFAULT_MAX_SUPPLY, address(0));

        assertEq(nft.name(), DEFAULT_NAME);
        assertEq(nft.symbol(), DEFAULT_SYMBOL);
        assertEq(nft.factory(), address(nftFactory));
        assertEq(nft.policy(), address(policy));
        assertEq(nft.creator(), agent);
        assertEq(nft.maxSupply(), DEFAULT_MAX_SUPPLY);
        assertEq(nft.baseURI(), DEFAULT_BASE_URI);
        assertEq(nft.metadataURI(), DEFAULT_METADATA_URI);
        assertEq(nft.metadataResolver(), address(0));
        assertEq(nft.totalMinted(), 0);
        assertTrue(nft.assetType() == AssetType.NFT);

        assertTrue(nftRegistry.isRegistered(address(nft)));
        assertEq(nftRegistry.policyOf(address(nft)), address(policy));
        assertEq(nftRegistry.creatorOf(address(nft)), agent);
    }

    function testCollectionCreatedEvent() public {
        vm.recordLogs();
        AgenticNFT nft = _createCollection(agent, address(0), DEFAULT_MAX_SUPPLY, address(0));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 topic = keccak256("CollectionCreated(address,address,address,uint256,address)");
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(nftFactory) || logs[i].topics[0] != topic) continue;
            assertEq(address(uint160(uint256(logs[i].topics[1]))), address(nft));
            assertEq(address(uint160(uint256(logs[i].topics[2]))), agent);
            assertEq(address(uint160(uint256(logs[i].topics[3]))), address(policy));
            (uint256 maxSupply_, address metadataResolver_) = abi.decode(logs[i].data, (uint256, address));
            assertEq(maxSupply_, DEFAULT_MAX_SUPPLY);
            assertEq(metadataResolver_, address(0));
            found = true;
        }
        assertTrue(found);
    }

    function testCreateCollectionThroughFrozenInterface() public {
        IAgentNFTFactory gated = IAgentNFTFactory(address(nftFactory));

        vm.prank(agent);
        address nft = gated.createCollection(
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            address(0),
            DEFAULT_MAX_SUPPLY,
            DEFAULT_BASE_URI,
            DEFAULT_METADATA_URI,
            address(0)
        );

        assertTrue(nftRegistry.isRegistered(nft));
        assertEq(IAgentNFT(nft).factory(), address(nftFactory));
    }

    function testCreateCollectionSelectorIsFrozen() public pure {
        assertEq(
            IAgentNFTFactory.createCollection.selector,
            bytes4(keccak256("createCollection(string,string,address,uint256,string,string,address)"))
        );
        assertEq(AgenticNFTFactory.createCollection.selector, IAgentNFTFactory.createCollection.selector);
    }

    // ---------------------------------------------------------------------
    // Policy resolution
    // ---------------------------------------------------------------------

    function testPolicyZeroResolvesCurrentPolicy() public {
        AgenticNFT nft = _createCollection(agent, address(0), DEFAULT_MAX_SUPPLY, address(0));
        assertEq(nft.policy(), address(policy));
        assertEq(nftRegistry.policyOf(address(nft)), address(policy));
    }

    function testExplicitAllowedPolicy() public {
        AgenticNFT nft = _createCollection(agent, address(policy), DEFAULT_MAX_SUPPLY, address(0));
        assertEq(nft.policy(), address(policy));
    }

    function testUnregisteredPolicyRejected() public {
        MockPolicy unknown = new MockPolicy(9);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFactory.PolicyNotAllowed.selector, address(unknown)));
        _createCollection(agent, address(unknown), DEFAULT_MAX_SUPPLY, address(0));
    }

    function testDeprecatedPolicyRejected() public {
        AgenticPolicy policy2 = new AgenticPolicy(address(identityRegistry), address(venue));
        policyRegistry.addPolicy(address(policy2), 2);
        policyRegistry.setCurrentPolicy(address(policy2));
        policyRegistry.deprecatePolicy(address(policy));

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFactory.PolicyNotAllowed.selector, address(policy)));
        _createCollection(agent, address(policy), DEFAULT_MAX_SUPPLY, address(0));
    }

    function testZeroCurrentPolicyRejected() public {
        AgenticPolicyRegistry emptyRegistry = new AgenticPolicyRegistry(address(this), 1);
        AgenticNFTFactory emptyFactory = new AgenticNFTFactory(address(emptyRegistry), address(nftRegistry));

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFactory.PolicyNotAllowed.selector, address(0)));
        emptyFactory.createCollection(
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            address(0),
            DEFAULT_MAX_SUPPLY,
            DEFAULT_BASE_URI,
            DEFAULT_METADATA_URI,
            address(0)
        );
    }

    // ---------------------------------------------------------------------
    // Supply and resolver
    // ---------------------------------------------------------------------

    function testZeroMaxSupplyRejected() public {
        vm.expectRevert(AgenticNFTFactory.ZeroSupply.selector);
        _createCollection(agent, address(0), 0, address(0));
    }

    function testMaxSupplyBoundaryStored() public {
        AgenticNFT one = _createCollection(agent, address(0), 1, address(0));
        assertEq(one.maxSupply(), 1);
        assertEq(one.totalMinted(), 0);

        AgenticNFT max = _createCollection(agent, address(0), type(uint256).max, address(0));
        assertEq(max.maxSupply(), type(uint256).max);
    }

    function testResolverZeroSelectsBaseURI() public {
        AgenticNFT nft = _createCollection(agent, address(0), DEFAULT_MAX_SUPPLY, address(0));
        assertEq(nft.metadataResolver(), address(0));
        assertEq(nft.baseURI(), DEFAULT_BASE_URI);
    }

    function testResolverContractStored() public {
        MockNFTMetadataResolver resolver = new MockNFTMetadataResolver();
        AgenticNFT nft = _createCollection(agent, address(0), DEFAULT_MAX_SUPPLY, address(resolver));
        assertEq(nft.metadataResolver(), address(resolver));
    }

    function testResolverEOARejected() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFactory.ResolverHasNoCode.selector, nonAgent));
        _createCollection(agent, address(0), DEFAULT_MAX_SUPPLY, nonAgent);
    }

    // ---------------------------------------------------------------------
    // Permissionless and consecutive creation
    // ---------------------------------------------------------------------

    function testNonAgentCanCreate() public {
        AgenticNFT nft = _createCollection(nonAgent, address(0), DEFAULT_MAX_SUPPLY, address(0));

        assertEq(nft.creator(), nonAgent);
        assertEq(nftRegistry.creatorOf(address(nft)), nonAgent);
        assertFalse(policy.isMember(nonAgent));
    }

    function testConsecutiveCollections() public {
        AgenticNFT first = _createCollection(agent, address(0), 10, address(0));
        AgenticNFT second = _createCollection(agent2, address(policy), 20, address(0));
        AgenticNFT third = _createCollection(nonAgent, address(0), 30, address(0));

        assertTrue(address(first) != address(second));
        assertTrue(address(second) != address(third));
        assertTrue(address(first) != address(third));

        assertEq(nftRegistry.creatorOf(address(first)), agent);
        assertEq(nftRegistry.creatorOf(address(second)), agent2);
        assertEq(nftRegistry.creatorOf(address(third)), nonAgent);
        assertEq(nftRegistry.policyOf(address(second)), address(policy));
        assertTrue(nftRegistry.isRegistered(address(third)));
    }

    // ---------------------------------------------------------------------
    // Atomic registration and no direct deployment
    // ---------------------------------------------------------------------

    function testCreationRevertsWhenFactoryIsNotNFTRegistrar() public {
        nftRegistry.setRegistrar(address(nftFactory), false);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTRegistry.NotRegistrar.selector, address(nftFactory)));
        _createCollection(agent, address(0), DEFAULT_MAX_SUPPLY, address(0));

        // The whole creation reverted before the success event was emitted.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 collectionCreated = keccak256("CollectionCreated(address,address,address,uint256,address)");
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != collectionCreated);
        }
    }

    function testDirectCollectionDeploymentReverts() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticNFT.NotFactory.selector, address(this)));
        new AgenticNFT(
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            address(nftFactory),
            address(policy),
            agent,
            DEFAULT_MAX_SUPPLY,
            DEFAULT_BASE_URI,
            DEFAULT_METADATA_URI,
            address(0)
        );
    }
}
