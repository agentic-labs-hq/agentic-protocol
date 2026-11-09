// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    FacilityCategory,
    NFT_ESCROW,
    NFT_GAME,
    NFT_LAUNCH,
    NFT_LOCKER,
    NFT_VAULT
} from "../../contracts/common/Types.sol";
import {AgenticNFTEscrowFacility} from "../../contracts/facility/AgenticNFTEscrowFacility.sol";
import {
    AgenticNFTEscrowTemplateDeployer,
    AgenticNFTFacilityFactory,
    AgenticNFTGameTemplateDeployer,
    AgenticNFTLaunchTemplateDeployer,
    AgenticNFTLockerTemplateDeployer,
    AgenticNFTVaultTemplateDeployer
} from "../../contracts/facility/AgenticNFTFacilityFactory.sol";
import {AgenticNFTGameFacility} from "../../contracts/facility/AgenticNFTGameFacility.sol";
import {AgenticNFTVaultFacility} from "../../contracts/facility/AgenticNFTVaultFacility.sol";
import {AgenticPolicyRegistry} from "../../contracts/policy/AgenticPolicyRegistry.sol";
import {AgenticNFTRegistry} from "../../contracts/registry/AgenticNFTRegistry.sol";
import {AgenticNFT} from "../../contracts/token/AgenticNFT.sol";
import {AgenticNFTFactory} from "../../contracts/token/AgenticNFTFactory.sol";
import {PolicyVenueFixture} from "../helpers/PolicyVenueFixture.sol";

/// @notice End-to-end NFT protocol flow against the real policy, venue registry
/// and identity adapter. No market, indexer or CLI is involved.
contract NFTProtocolFlowTest is PolicyVenueFixture {
    AgenticPolicyRegistry internal policyRegistry;
    AgenticNFTRegistry internal nftRegistry;
    AgenticNFTFactory internal nftFactory;
    AgenticNFTFacilityFactory internal nftFacilityFactory;

    address internal nftVault;
    address internal nftGame;
    address internal nftEscrow;

    address internal operator = address(0x0BEEF);

    function setUp() public {
        _deployPolicyVenue();

        policyRegistry = new AgenticPolicyRegistry(address(this), 8);
        policyRegistry.addPolicy(address(policy), 1);
        policyRegistry.setCurrentPolicy(address(policy));

        nftRegistry = new AgenticNFTRegistry(address(this), address(policyRegistry));

        AgenticNFTFacilityFactory.TemplateDeployers memory deployers = AgenticNFTFacilityFactory.TemplateDeployers({
            vault: address(new AgenticNFTVaultTemplateDeployer()),
            launch: address(new AgenticNFTLaunchTemplateDeployer()),
            locker: address(new AgenticNFTLockerTemplateDeployer()),
            game: address(new AgenticNFTGameTemplateDeployer()),
            escrow: address(new AgenticNFTEscrowTemplateDeployer())
        });
        nftFacilityFactory =
            new AgenticNFTFacilityFactory(address(policy), address(venue), address(nftRegistry), deployers);

        venue.addTypeCategory(NFT_VAULT, FacilityCategory.CUSTODY);
        venue.addTypeCategory(NFT_LAUNCH, FacilityCategory.CUSTODY);
        venue.addTypeCategory(NFT_LOCKER, FacilityCategory.CUSTODY);
        venue.addTypeCategory(NFT_GAME, FacilityCategory.PURPOSE);
        venue.addTypeCategory(NFT_ESCROW, FacilityCategory.PURPOSE);
        venue.setRegistrar(address(nftFacilityFactory), FacilityCategory.CUSTODY, true);
        venue.setRegistrar(address(nftFacilityFactory), FacilityCategory.PURPOSE, true);

        nftFactory = new AgenticNFTFactory(address(policyRegistry), address(nftRegistry));
        nftRegistry.setRegistrar(address(nftFactory), true);

        nftVault = nftFacilityFactory.createFacility(NFT_VAULT, abi.encode(projectOwner));
        nftGame = nftFacilityFactory.createFacility(NFT_GAME, abi.encode(projectOwner, operator));
        nftEscrow = nftFacilityFactory.createFacility(NFT_ESCROW, abi.encode(projectOwner, operator, agent2));
    }

    function _createCollection(uint256 maxSupply) internal returns (AgenticNFT nft) {
        vm.prank(agent);
        nft = AgenticNFT(
            nftFactory.createCollection(
                "Agent Sword", "ASW", address(0), maxSupply, "ipfs://base/", "ipfs://collection.json", address(0)
            )
        );
    }

    function testCollectionIssuanceAndRegistryStamps() public {
        AgenticNFT nft = _createCollection(10);

        assertEq(nft.creator(), agent);
        assertEq(nft.policy(), address(policy));
        assertEq(nft.maxSupply(), 10);
        assertEq(nft.totalMinted(), 0);
        assertEq(uint256(nft.assetType()), uint256(1)); // AssetType.NFT

        assertTrue(nftRegistry.isRegistered(address(nft)));
        assertEq(nftRegistry.policyOf(address(nft)), address(policy));
        assertEq(nftRegistry.creatorOf(address(nft)), agent);

        vm.prank(agent);
        nft.mint(agent, 3);
        assertEq(nft.totalMinted(), 3);
        assertEq(nft.ownerOf(0), agent);
        assertEq(nft.ownerOf(2), agent);
        assertEq(nft.tokenURI(2), "ipfs://base/2");
    }

    function testMintIsCreatorOnlyAndCapped() public {
        AgenticNFT nft = _createCollection(2);

        vm.prank(agent2);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFT.NotCreator.selector, agent2));
        nft.mint(agent2, 1);

        vm.prank(agent);
        nft.mint(agent, 2);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFT.InvalidSupply.selector, 1, 0));
        nft.mint(agent, 1);
    }

    function testBatchMint() public {
        AgenticNFT nft = _createCollection(10);
        address[] memory recipients = new address[](2);
        uint256[] memory counts = new uint256[](2);
        recipients[0] = agent;
        recipients[1] = agent2;
        counts[0] = 2;
        counts[1] = 1;

        vm.prank(agent);
        nft.mintBatch(recipients, counts);

        assertEq(nft.ownerOf(0), agent);
        assertEq(nft.ownerOf(1), agent);
        assertEq(nft.ownerOf(2), agent2);
        assertEq(nft.totalMinted(), 3);
    }

    function testAgentTransferAllowedNonAgentDenied() public {
        AgenticNFT nft = _createCollection(10);
        vm.prank(agent);
        nft.mint(agent, 2);

        vm.prank(agent);
        nft.transferFrom(agent, agent2, 0);
        assertEq(nft.ownerOf(0), agent2);

        vm.prank(agent);
        vm.expectRevert();
        nft.transferFrom(agent, nonAgent, 1);
    }

    function testAgentCannotDepositIntoVault() public {
        AgenticNFT nft = _createCollection(10);
        vm.prank(agent);
        nft.mint(agent, 1);

        vm.prank(agent);
        vm.expectRevert();
        nft.transferFrom(agent, nftVault, 0);
    }

    function testVaultMintAndRelease() public {
        AgenticNFT nft = _createCollection(10);

        vm.prank(agent);
        nft.mint(nftVault, 1);
        assertEq(nft.ownerOf(0), nftVault);

        vm.prank(projectOwner);
        AgenticNFTVaultFacility(nftVault).release(address(nft), 0, agent2);
        assertEq(nft.ownerOf(0), agent2);
    }

    function testGameDepositConsumeAndRelease() public {
        AgenticNFT nft = _createCollection(10);
        vm.prank(agent);
        nft.mint(agent, 3);

        vm.prank(agent);
        nft.safeTransferFrom(agent, nftGame, 0);
        vm.prank(agent);
        nft.safeTransferFrom(agent, nftGame, 1);

        vm.prank(operator);
        AgenticNFTGameFacility(nftGame).consume(address(nft), 0);

        vm.prank(operator);
        vm.expectRevert();
        AgenticNFTGameFacility(nftGame).release(address(nft), 0, agent2);

        vm.prank(operator);
        AgenticNFTGameFacility(nftGame).release(address(nft), 1, agent2);
        assertEq(nft.ownerOf(1), agent2);
    }

    function testEscrowSettlesOnce() public {
        AgenticNFT nft = _createCollection(10);
        vm.prank(agent);
        nft.mint(agent, 1);

        vm.prank(agent);
        nft.safeTransferFrom(agent, nftEscrow, 0);

        vm.prank(operator);
        AgenticNFTEscrowFacility(nftEscrow).release(address(nft), 0, agent2);
        assertEq(nft.ownerOf(0), agent2);

        vm.prank(operator);
        vm.expectRevert();
        AgenticNFTEscrowFacility(nftEscrow).refund(address(nft), 0, agent);
    }

    function testFacilityVenueStamps() public view {
        assertTrue(venue.isFacilityOfCategory(nftVault, FacilityCategory.CUSTODY));
        assertTrue(venue.isFacilityOfCategory(nftGame, FacilityCategory.PURPOSE));
        assertTrue(venue.isFacilityOfCategory(nftEscrow, FacilityCategory.PURPOSE));
        assertEq(venue.facilityType(nftVault), NFT_VAULT);
        assertEq(venue.facilityType(nftGame), NFT_GAME);
        assertEq(venue.facilityType(nftEscrow), NFT_ESCROW);
    }

    function testResolverMetadataMode() public {
        MockResolver resolver = new MockResolver();
        vm.prank(agent);
        AgenticNFT nft = AgenticNFT(
            nftFactory.createCollection("UGC", "UGC", address(0), 10, "", "ipfs://collection.json", address(resolver))
        );

        vm.prank(agent);
        nft.mint(agent, 1);
        assertEq(nft.tokenURI(0), "ipfs://resolved/0");
    }
}

/// @notice Minimal immutable metadata resolver used by the integration test.
contract MockResolver {
    function tokenURI(address, uint256 tokenId) external pure returns (string memory) {
        return string.concat("ipfs://resolved/", tokenId == 0 ? "0" : "x");
    }
}
