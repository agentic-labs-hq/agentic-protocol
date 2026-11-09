// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {IAgentmarket} from "../../contracts/interfaces/IAgentmarket.sol";
import {Agentmarket} from "../../contracts/market/Agentmarket.sol";
import {AgenticPolicyRegistry} from "../../contracts/policy/AgenticPolicyRegistry.sol";
import {AgenticNFTRegistry} from "../../contracts/registry/AgenticNFTRegistry.sol";
import {AgenticNFT} from "../../contracts/token/AgenticNFT.sol";
import {AgenticNFTFactory} from "../../contracts/token/AgenticNFTFactory.sol";
import {TREASURY} from "../../contracts/common/Types.sol";
import {PolicyVenueFixture} from "../helpers/PolicyVenueFixture.sol";

/// @notice End-to-end Agentmarket flow against the real NFT protocol stack
/// (policy, identity, NFT registry, NFT factory, venue registry).
contract AgentmarketFlowTest is PolicyVenueFixture {
    AgenticPolicyRegistry internal policyRegistry;
    AgenticNFTRegistry internal nftRegistry;
    AgenticNFTFactory internal nftFactory;
    Agentmarket internal market;
    AgentmarketFeeTreasury internal treasury;
    AgenticNFT internal nft;

    function setUp() public {
        _deployPolicyVenue();

        policyRegistry = new AgenticPolicyRegistry(address(this), 8);
        policyRegistry.addPolicy(address(policy), 1);
        policyRegistry.setCurrentPolicy(address(policy));

        nftRegistry = new AgenticNFTRegistry(address(this), address(policyRegistry));
        nftFactory = new AgenticNFTFactory(address(policyRegistry), address(nftRegistry));
        nftRegistry.setRegistrar(address(nftFactory), true);

        treasury = new AgentmarketFeeTreasury();
        venue.registerFacility(address(treasury), TREASURY);

        market = new Agentmarket(address(this), address(nftRegistry), address(venue), address(treasury), 100);

        vm.prank(agent);
        nft = AgenticNFT(
            nftFactory.createCollection(
                "Agent Sword", "ASW", address(0), 10, "ipfs://base/", "ipfs://collection.json", address(0)
            )
        );
        vm.prank(agent);
        nft.mint(agent, 3);
    }

    function _list(address seller, uint256 tokenId, uint256 price, uint64 deadline) internal {
        vm.prank(seller);
        market.list(address(nft), tokenId, price, deadline);
    }

    function _approve(address seller, uint256 tokenId) internal {
        vm.prank(seller);
        nft.approve(address(market), tokenId);
    }

    function testListAndBuySettlesAtomically() public {
        _list(agent, 0, 1 ether, 0);
        _approve(agent, 0);

        assertEq(market.nonceOf(agent), 1);
        IAgentmarket.Listing memory listing = market.listingOf(address(nft), 0);
        assertEq(listing.order.seller, agent);
        assertEq(listing.order.price, 1 ether);
        assertEq(listing.feeBps, 100);
        assertTrue(listing.active);
        assertTrue(market.isExecutable(address(nft), 0));

        vm.deal(agent2, 1 ether);
        uint256 sellerBefore = agent.balance;
        uint256 treasuryBefore = address(treasury).balance;

        vm.prank(agent2);
        market.buy{value: 1 ether}(address(nft), 0);

        assertEq(nft.ownerOf(0), agent2);
        assertEq(agent.balance, sellerBefore + 0.99 ether);
        assertEq(address(treasury).balance, treasuryBefore + 0.01 ether);
        assertFalse(market.listingOf(address(nft), 0).active);
    }

    function testNonAgentBuyerIsDeniedByPolicy() public {
        _list(agent, 0, 1 ether, 0);
        _approve(agent, 0);

        vm.deal(nonAgent, 1 ether);
        vm.prank(nonAgent);
        vm.expectRevert();
        market.buy{value: 1 ether}(address(nft), 0);
    }

    function testStaleListingRevertsAndNewOwnerCanOverwrite() public {
        _list(agent, 0, 1 ether, 0);
        _approve(agent, 0);

        // Seller moves the token after listing.
        vm.prank(agent);
        nft.transferFrom(agent, agent2, 0);
        assertFalse(market.isExecutable(address(nft), 0));

        vm.deal(agent2, 1 ether);
        vm.prank(agent2);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.SellerNoLongerOwner.selector, address(nft), 0));
        market.buy{value: 1 ether}(address(nft), 0);

        // New owner re-lists the same token id; the stale record is replaced.
        _list(agent2, 0, 2 ether, 0);
        _approve(agent2, 0);
        IAgentmarket.Listing memory listing = market.listingOf(address(nft), 0);
        assertEq(listing.order.seller, agent2);
        assertEq(listing.order.price, 2 ether);
        assertEq(listing.order.nonce, 1);

        vm.deal(agent, 2 ether);
        vm.prank(agent);
        market.buy{value: 2 ether}(address(nft), 0);
        assertEq(nft.ownerOf(0), agent);
    }

    function testBuyerWithoutAgentIdIsDenied() public {
        _list(agent, 0, 1 ether, 0);
        _approve(agent, 0);

        identityAdapter.setHasIdentity(agent2, false);
        vm.deal(agent2, 1 ether);
        vm.prank(agent2);
        vm.expectRevert();
        market.buy{value: 1 ether}(address(nft), 0);
    }

    function testFeeSnapshotSurvivesGovernanceChange() public {
        _list(agent, 0, 1 ether, 0);
        _approve(agent, 0);

        market.setFeeBps(500);
        assertEq(market.feeBps(), 500);

        vm.deal(agent2, 1 ether);
        vm.prank(agent2);
        market.buy{value: 1 ether}(address(nft), 0);

        // 1% snapshot, not the new 5%.
        assertEq(address(treasury).balance, 0.01 ether);
    }

    function testTreasuryMigrationAppliesToSettlement() public {
        AgentmarketFeeTreasury next = new AgentmarketFeeTreasury();
        venue.registerFacility(address(next), TREASURY);

        _list(agent, 0, 1 ether, 0);
        _approve(agent, 0);

        market.setTreasury(address(next));
        assertEq(market.treasury(), address(next));

        vm.deal(agent2, 1 ether);
        vm.prank(agent2);
        market.buy{value: 1 ether}(address(nft), 0);

        assertEq(address(treasury).balance, 0);
        assertEq(address(next).balance, 0.01 ether);
    }

    function testUnregisteredCollectionCannotBeListed() public {
        AgentmarketUnregisteredNFT raw = new AgentmarketUnregisteredNFT();
        raw.mint(agent, 0);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.CollectionNotRegistered.selector, address(raw)));
        market.list(address(raw), 0, 1 ether, 0);
    }

    function testIsExecutableReflectsApprovalAndDeadline() public {
        _list(agent, 0, 1 ether, uint64(block.timestamp + 1 days));
        assertFalse(market.isExecutable(address(nft), 0)); // not approved

        _approve(agent, 0);
        assertTrue(market.isExecutable(address(nft), 0));

        vm.warp(block.timestamp + 2 days);
        assertFalse(market.isExecutable(address(nft), 0)); // expired
    }

    function testCancelClearsListing() public {
        _list(agent, 0, 1 ether, 0);

        vm.prank(agent2);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.NotSeller.selector, address(nft), 0, agent2));
        market.cancel(address(nft), 0);

        vm.prank(agent);
        market.cancel(address(nft), 0);
        assertFalse(market.listingOf(address(nft), 0).active);
        assertFalse(market.isExecutable(address(nft), 0));
    }

    function testFeeRoundingFavorsSeller() public {
        _list(agent, 0, 101, 0);
        _approve(agent, 0);

        vm.deal(agent2, 101);
        uint256 sellerBefore = agent.balance;
        uint256 treasuryBefore = address(treasury).balance;

        vm.prank(agent2);
        market.buy{value: 101}(address(nft), 0);

        assertEq(agent.balance, sellerBefore + 100);
        assertEq(address(treasury).balance, treasuryBefore + 1);
    }

    function testMarketRejectsDirectNativeTransfers() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(market).call{value: 1 ether}("");
        assertFalse(ok);
    }

    function testSellerRejectsPaymentAndWholeBuyRollsBack() public {
        AgentmarketRejectingSeller rejectingSeller = new AgentmarketRejectingSeller();
        identityAdapter.setHasIdentity(address(rejectingSeller), true);

        uint256 tokenId = nft.totalMinted();
        vm.prank(agent);
        nft.mint(address(rejectingSeller), 1);

        rejectingSeller.listAndApprove(market, nft, tokenId, 1 ether);
        Agentmarket.Listing memory listingBefore = market.listingOf(address(nft), tokenId);
        assertTrue(listingBefore.active);

        vm.deal(agent2, 1 ether);
        vm.prank(agent2);
        vm.expectRevert();
        market.buy{value: 1 ether}(address(nft), tokenId);

        assertEq(nft.ownerOf(tokenId), address(rejectingSeller));
        assertTrue(market.listingOf(address(nft), tokenId).active);
        assertEq(address(market).balance, 0);
        assertEq(agent2.balance, 1 ether);
    }

    function testTreasuryRejectsPaymentAndWholeBuyRollsBack() public {
        AgentmarketRejectingTreasury rejectingTreasury = new AgentmarketRejectingTreasury();
        venue.registerFacility(address(rejectingTreasury), TREASURY);
        market.setTreasury(address(rejectingTreasury));

        _list(agent, 0, 1 ether, 0);
        _approve(agent, 0);

        vm.deal(agent2, 1 ether);
        uint256 sellerBefore = agent.balance;
        vm.prank(agent2);
        vm.expectRevert();
        market.buy{value: 1 ether}(address(nft), 0);

        assertEq(nft.ownerOf(0), agent);
        assertTrue(market.listingOf(address(nft), 0).active);
        assertEq(agent.balance, sellerBefore);
        assertEq(address(market).balance, 0);
    }

    function testRevokedTreasuryStillReceivesUntilMigration() public {
        AgentmarketFeeTreasury revoked = new AgentmarketFeeTreasury();
        AgentmarketFeeTreasury replacement = new AgentmarketFeeTreasury();
        venue.registerFacility(address(revoked), TREASURY);
        venue.registerFacility(address(replacement), TREASURY);
        market.setTreasury(address(revoked));

        venue.revokeFacility(address(revoked));

        _list(agent, 0, 1 ether, 0);
        _approve(agent, 0);
        vm.deal(agent2, 1 ether);
        vm.prank(agent2);
        market.buy{value: 1 ether}(address(nft), 0);
        assertEq(address(revoked).balance, 0.01 ether);

        market.setTreasury(address(replacement));
        _list(agent, 1, 1 ether, 0);
        _approve(agent, 1);
        vm.deal(agent2, 1 ether);
        vm.prank(agent2);
        market.buy{value: 1 ether}(address(nft), 1);
        assertEq(address(replacement).balance, 0.01 ether);
    }

    function testIsExecutableApprovalEdges() public {
        _list(agent, 0, 1 ether, 0);
        assertFalse(market.isExecutable(address(nft), 0));

        vm.prank(agent);
        nft.approve(agent2, 0);
        assertFalse(market.isExecutable(address(nft), 0));

        vm.prank(agent);
        nft.approve(address(market), 0);
        assertTrue(market.isExecutable(address(nft), 0));

        vm.prank(agent);
        nft.approve(address(0), 0);
        assertFalse(market.isExecutable(address(nft), 0));

        vm.prank(agent);
        nft.setApprovalForAll(address(market), true);
        assertTrue(market.isExecutable(address(nft), 0));

        vm.prank(agent);
        nft.setApprovalForAll(address(market), false);
        assertFalse(market.isExecutable(address(nft), 0));
    }

    function testOldSellerCannotCancelAfterNewOwnerRelists() public {
        _list(agent, 0, 1 ether, 0);
        vm.prank(agent);
        nft.transferFrom(agent, agent2, 0);

        _list(agent2, 0, 2 ether, 0);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.NotSeller.selector, address(nft), 0, agent));
        market.cancel(address(nft), 0);
    }

    function testGovernanceOnlySetters() public {
        vm.prank(agent);
        vm.expectRevert();
        market.setFeeBps(100);

        vm.prank(agent);
        vm.expectRevert();
        market.setTreasury(address(treasury));
    }
}

/// @notice Minimal BNB-receiving fee recipient used by the integration test.
contract AgentmarketFeeTreasury {
    receive() external payable {}
}

/// @notice Seller contract that rejects BNB, used to prove atomic rollback.
contract AgentmarketRejectingSeller {
    function listAndApprove(Agentmarket market, IERC721 nft, uint256 tokenId, uint256 price) external {
        market.list(address(nft), tokenId, price, 0);
        nft.approve(address(market), tokenId);
    }

    receive() external payable {
        revert("no bnb");
    }
}

/// @notice Fee recipient that rejects BNB, used to prove atomic rollback.
contract AgentmarketRejectingTreasury {
    receive() external payable {
        revert("no bnb");
    }
}

/// @notice Non-protocol NFT used to prove the provenance check.
contract AgentmarketUnregisteredNFT is ERC721 {
    constructor() ERC721("Raw", "RAW") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}
