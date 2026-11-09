// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {Governance2Step} from "../../contracts/common/Governance2Step.sol";
import {AgenticNFT} from "../../contracts/token/AgenticNFT.sol";
import {AgenticNFTRegistry} from "../../contracts/registry/AgenticNFTRegistry.sol";
import {AssetType} from "../../contracts/common/Types.sol";

import {MockAgentNFT} from "../mocks/MockAgentNFT.sol";
import {MockPolicy} from "../mocks/MockPolicy.sol";
import {NFTAssetFixture} from "../helpers/NFTAssetFixture.sol";

contract AgenticNFTRegistryTest is NFTAssetFixture {
    event AssetRegistered(address indexed nft, address indexed policy, address indexed creator);
    event RegistrarSet(address indexed account, bool enabled);

    function setUp() public {
        _deployNFTAsset();
    }

    // ---------------------------------------------------------------------
    // Construction and configuration
    // ---------------------------------------------------------------------

    function testInitialState() public view {
        assertEq(nftRegistry.governance(), address(this));
        assertEq(nftRegistry.pendingGovernance(), address(0));
        assertEq(nftRegistry.policyRegistry(), address(policyRegistry));
        assertTrue(nftRegistry.isRegistrar(address(nftFactory)));
        assertFalse(nftRegistry.isRegistrar(address(nftRegistrar)));
    }

    function testConstructorRejectsZeroGovernance() public {
        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        new AgenticNFTRegistry(address(0), address(policyRegistry));
    }

    function testConstructorRejectsZeroPolicyRegistry() public {
        vm.expectRevert(AgenticNFTRegistry.ZeroRegistry.selector);
        new AgenticNFTRegistry(address(this), address(0));
    }

    function testConstructorRejectsCodelessPolicyRegistry() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTRegistry.RegistryHasNoCode.selector, nonAgent));
        new AgenticNFTRegistry(address(this), nonAgent);
    }

    function testSetRegistrar() public {
        vm.expectEmit(true, false, false, true, address(nftRegistry));
        emit RegistrarSet(address(nftRegistrar), true);
        nftRegistry.setRegistrar(address(nftRegistrar), true);
        assertTrue(nftRegistry.isRegistrar(address(nftRegistrar)));

        vm.expectEmit(true, false, false, true, address(nftRegistry));
        emit RegistrarSet(address(nftRegistrar), false);
        nftRegistry.setRegistrar(address(nftRegistrar), false);
        assertFalse(nftRegistry.isRegistrar(address(nftRegistrar)));
    }

    function testSetRegistrarOnlyGovernance() public {
        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonAgent));
        nftRegistry.setRegistrar(address(nftRegistrar), true);
    }

    function testSetRegistrarRejectsZero() public {
        vm.expectRevert(AgenticNFTRegistry.ZeroRegistrar.selector);
        nftRegistry.setRegistrar(address(0), true);
    }

    function testSetRegistrarRejectsCodeless() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTRegistry.RegistrarHasNoCode.selector, nonAgent));
        nftRegistry.setRegistrar(nonAgent, true);
    }

    function testDisabledRegistrarRejected() public {
        nftRegistry.setRegistrar(address(nftRegistrar), true);
        nftRegistry.setRegistrar(address(nftRegistrar), false);

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTRegistry.NotRegistrar.selector, address(nftRegistrar)));
        nftRegistrar.register(address(nftRegistry), address(0xBEEF), address(policy), agent);
    }

    function testGovernanceTwoStep() public {
        address newGov = address(0xC0FFEE);
        nftRegistry.transferGovernance(newGov);
        assertEq(nftRegistry.pendingGovernance(), newGov);

        vm.prank(newGov);
        nftRegistry.acceptGovernance();
        assertEq(nftRegistry.governance(), newGov);

        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, address(this)));
        nftRegistry.setRegistrar(address(nftRegistrar), true);
    }

    // ---------------------------------------------------------------------
    // Registration authorization and stamps
    // ---------------------------------------------------------------------

    function testFactoryCreatedCollectionIsRegistered() public {
        AgenticNFT nft = _createRegisteredCollection();

        assertTrue(nftRegistry.isRegistered(address(nft)));
        assertEq(nftRegistry.policyOf(address(nft)), address(policy));
        assertEq(nftRegistry.creatorOf(address(nft)), agent);
    }

    function testFactoryCreatedCollectionRegisteredEvent() public {
        vm.recordLogs();
        AgenticNFT nft = _createRegisteredCollection();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 topic = keccak256("AssetRegistered(address,address,address)");
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(nftRegistry) || logs[i].topics[0] != topic) continue;
            assertEq(address(uint160(uint256(logs[i].topics[1]))), address(nft));
            assertEq(address(uint160(uint256(logs[i].topics[2]))), address(policy));
            assertEq(address(uint160(uint256(logs[i].topics[3]))), agent);
            found = true;
        }
        assertTrue(found);
    }

    function testNonRegistrarRejected() public {
        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTRegistry.NotRegistrar.selector, nonAgent));
        nftRegistry.registerAsset(address(0xBEEF), address(policy), agent);
    }

    function testZeroAssetRejected() public {
        nftRegistry.setRegistrar(address(nftRegistrar), true);

        vm.expectRevert(AgenticNFTRegistry.ZeroAsset.selector);
        nftRegistrar.register(address(nftRegistry), address(0), address(policy), agent);
    }

    function testCodelessAssetRejected() public {
        nftRegistry.setRegistrar(address(nftRegistrar), true);

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTRegistry.AssetHasNoCode.selector, nonAgent));
        nftRegistrar.register(address(nftRegistry), nonAgent, address(policy), agent);
    }

    function testFactoryMismatchRejected() public {
        nftRegistry.setRegistrar(address(nftRegistrar), true);
        // Self-factory stamp: the registrar calling is not the collection's factory.
        MockAgentNFT nft = _newMockNFT(address(0), address(policy), agent, AssetType.NFT);

        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticNFTRegistry.FactoryMismatch.selector, address(nft), address(nftRegistrar), address(nft)
            )
        );
        nftRegistrar.register(address(nftRegistry), address(nft), address(policy), agent);
    }

    function testPolicyMismatchRejected() public {
        MockAgentNFT nft = _newMockNFT(address(0), address(policy), agent, AssetType.NFT);
        nftRegistry.setRegistrar(address(nft), true);

        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticNFTRegistry.PolicyMismatch.selector, address(nft), address(0xDEAD), address(policy)
            )
        );
        nft.registerOn(address(nftRegistry), address(0xDEAD), agent);
    }

    function testPolicyNotAllowedRejected() public {
        MockPolicy unknown = new MockPolicy(7);
        MockAgentNFT nft = _newMockNFT(address(0), address(unknown), agent, AssetType.NFT);
        nftRegistry.setRegistrar(address(nft), true);

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTRegistry.PolicyNotAllowed.selector, address(unknown)));
        nft.registerOn(address(nftRegistry), address(unknown), agent);
    }

    function testCreatorMismatchRejected() public {
        MockAgentNFT nft = _newMockNFT(address(0), address(policy), agent, AssetType.NFT);
        nftRegistry.setRegistrar(address(nft), true);

        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTRegistry.CreatorMismatch.selector, address(nft), agent2, agent)
        );
        nft.registerOn(address(nftRegistry), address(policy), agent2);
    }

    function testNonNFTAssetRejected() public {
        MockAgentNFT nft = _newMockNFT(address(0), address(policy), agent, AssetType.FT);
        nftRegistry.setRegistrar(address(nft), true);

        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTRegistry.AssetTypeNotSupported.selector, address(nft), AssetType.FT)
        );
        nft.registerOn(address(nftRegistry), address(policy), agent);
    }

    function testMockCollectionRegistrationRecordsStamps() public {
        nftRegistry.setRegistrar(address(nftRegistrar), true);
        MockAgentNFT nft = _newMockNFT(address(nftRegistrar), address(policy), agent, AssetType.NFT);

        vm.expectEmit(true, true, true, true, address(nftRegistry));
        emit AssetRegistered(address(nft), address(policy), agent);
        nftRegistrar.register(address(nftRegistry), address(nft), address(policy), agent);

        assertTrue(nftRegistry.isRegistered(address(nft)));
        assertEq(nftRegistry.policyOf(address(nft)), address(policy));
        assertEq(nftRegistry.creatorOf(address(nft)), agent);
    }

    function testDuplicateAssetRejected() public {
        nftRegistry.setRegistrar(address(nftRegistrar), true);
        MockAgentNFT nft = _newMockNFT(address(nftRegistrar), address(policy), agent, AssetType.NFT);
        nftRegistrar.register(address(nftRegistry), address(nft), address(policy), agent);

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTRegistry.AssetAlreadyRegistered.selector, address(nft)));
        nftRegistrar.register(address(nftRegistry), address(nft), address(policy), agent);
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _newMockNFT(address factory_, address policy_, address creator_, AssetType assetType_)
        internal
        returns (MockAgentNFT nft)
    {
        nft = new MockAgentNFT(factory_, policy_, creator_, assetType_);
    }
}
