// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssetType} from "../../contracts/common/Types.sol";
import {AgenticNFT} from "../../contracts/token/AgenticNFT.sol";
import {PolicyVenueFixture} from "../helpers/PolicyVenueFixture.sol";

/// @notice Focused unit tests for the gated NFT collection itself.
contract AgenticNFTTest is PolicyVenueFixture {
    address internal constant COLLECTION_FACTORY = address(0xFACA);

    function setUp() public {
        _deployPolicyVenue();
    }

    function _deploy(uint256 maxSupply) internal returns (AgenticNFT nft) {
        vm.prank(COLLECTION_FACTORY);
        nft = new AgenticNFT(
            "Agent Sword",
            "ASW",
            COLLECTION_FACTORY,
            address(policy),
            agent,
            maxSupply,
            "ipfs://base/",
            "ipfs://collection.json",
            address(0)
        );
    }

    function testConstructorStamps() public {
        AgenticNFT nft = _deploy(10);

        assertEq(nft.name(), "Agent Sword");
        assertEq(nft.symbol(), "ASW");
        assertEq(nft.factory(), COLLECTION_FACTORY);
        assertEq(nft.policy(), address(policy));
        assertEq(nft.creator(), agent);
        assertEq(nft.maxSupply(), 10);
        assertEq(nft.totalMinted(), 0);
        assertEq(nft.baseURI(), "ipfs://base/");
        assertEq(nft.metadataURI(), "ipfs://collection.json");
        assertEq(nft.metadataResolver(), address(0));
        assertEq(uint256(nft.assetType()), uint256(AssetType.NFT));
    }

    function testConstructorRejectsForeignDeployer() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticNFT.NotFactory.selector, address(this)));
        new AgenticNFT("Agent Sword", "ASW", COLLECTION_FACTORY, address(policy), agent, 10, "", "", address(0));
    }

    function testConstructorRejectsZeroSupply() public {
        vm.prank(COLLECTION_FACTORY);
        vm.expectRevert(AgenticNFT.ZeroSupply.selector);
        new AgenticNFT("N", "N", COLLECTION_FACTORY, address(policy), agent, 0, "", "", address(0));
    }

    function testConstructorRejectsZeroPolicyOrCreator() public {
        vm.prank(COLLECTION_FACTORY);
        vm.expectRevert(AgenticNFT.InvalidConfiguration.selector);
        new AgenticNFT("N", "N", COLLECTION_FACTORY, address(0), agent, 1, "", "", address(0));

        vm.prank(COLLECTION_FACTORY);
        vm.expectRevert(AgenticNFT.InvalidConfiguration.selector);
        new AgenticNFT("N", "N", COLLECTION_FACTORY, address(policy), address(0), 1, "", "", address(0));
    }

    function testMintIsCreatorOnly() public {
        AgenticNFT nft = _deploy(10);

        vm.prank(agent2);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFT.NotCreator.selector, agent2));
        nft.mint(agent2, 1);
    }

    function testMintCap() public {
        AgenticNFT nft = _deploy(2);

        vm.prank(agent);
        nft.mint(agent, 2);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFT.InvalidSupply.selector, 1, 0));
        nft.mint(agent, 1);
    }

    function testMintZeroCount() public {
        AgenticNFT nft = _deploy(2);

        vm.prank(agent);
        vm.expectRevert(AgenticNFT.ZeroCount.selector);
        nft.mint(agent, 0);
    }

    function testMintToNonAgentDenied() public {
        AgenticNFT nft = _deploy(2);

        vm.prank(agent);
        vm.expectRevert();
        nft.mint(nonAgent, 1);
    }

    function testMintBatchLengthMismatch() public {
        AgenticNFT nft = _deploy(2);
        address[] memory recipients = new address[](1);
        uint256[] memory counts = new uint256[](2);

        vm.prank(agent);
        vm.expectRevert(AgenticNFT.LengthMismatch.selector);
        nft.mintBatch(recipients, counts);
    }

    function testMintBatchSkipsZeroCounts() public {
        AgenticNFT nft = _deploy(3);
        address[] memory recipients = new address[](3);
        uint256[] memory counts = new uint256[](3);
        recipients[0] = agent;
        recipients[1] = agent2;
        recipients[2] = agent;
        counts[0] = 1;
        counts[1] = 0;
        counts[2] = 2;

        vm.prank(agent);
        nft.mintBatch(recipients, counts);

        assertEq(nft.ownerOf(0), agent);
        assertEq(nft.ownerOf(1), agent);
        assertEq(nft.ownerOf(2), agent);
        assertEq(nft.totalMinted(), 3);
    }

    function testMintBatchCap() public {
        AgenticNFT nft = _deploy(2);
        address[] memory recipients = new address[](1);
        uint256[] memory counts = new uint256[](1);
        recipients[0] = agent;
        counts[0] = 3;

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFT.InvalidSupply.selector, 3, 2));
        nft.mintBatch(recipients, counts);
    }

    function testApprovedOperatorCanTransfer() public {
        AgenticNFT nft = _deploy(2);
        vm.prank(agent);
        nft.mint(agent, 1);

        vm.prank(agent);
        nft.approve(agent2, 0);

        vm.prank(agent2);
        nft.transferFrom(agent, agent2, 0);
        assertEq(nft.ownerOf(0), agent2);
    }

    function testTokenURIBaseMode() public {
        AgenticNFT nft = _deploy(2);
        vm.prank(agent);
        nft.mint(agent, 2);

        assertEq(nft.tokenURI(0), "ipfs://base/0");
        assertEq(nft.tokenURI(1), "ipfs://base/1");
    }

    function testTokenURIResolverMode() public {
        MockNFTMetadataResolver resolver = new MockNFTMetadataResolver();
        vm.prank(COLLECTION_FACTORY);
        AgenticNFT nft =
            new AgenticNFT("UGC", "UGC", COLLECTION_FACTORY, address(policy), agent, 2, "", "", address(resolver));

        vm.prank(agent);
        nft.mint(agent, 1);
        assertEq(nft.tokenURI(0), "ipfs://resolved/0");
    }

    function testTokenURINonexistentTokenReverts() public {
        AgenticNFT nft = _deploy(2);
        vm.expectRevert();
        nft.tokenURI(0);
    }
}

contract MockNFTMetadataResolver {
    function tokenURI(address, uint256 tokenId) external pure returns (string memory) {
        return string.concat("ipfs://resolved/", tokenId == 0 ? "0" : "x");
    }
}
