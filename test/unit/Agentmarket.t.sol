// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {Governance2Step} from "../../contracts/common/Governance2Step.sol";
import {IAgentmarket} from "../../contracts/interfaces/IAgentmarket.sol";
import {Agentmarket} from "../../contracts/market/Agentmarket.sol";

import {AgentmarketFixture} from "../helpers/AgentmarketFixture.sol";
import {MockMarketNFT} from "../mocks/MockMarketNFT.sol";
import {MockMarketTreasury} from "../mocks/MockMarketTreasury.sol";

contract AgentmarketTest is AgentmarketFixture {
    event Listed(
        address indexed collection,
        uint256 indexed tokenId,
        address indexed seller,
        uint256 price,
        uint16 feeBps,
        address paymentAsset,
        uint64 deadline,
        uint64 nonce
    );
    event Cancelled(address indexed collection, uint256 indexed tokenId, address indexed seller);
    event Sold(
        address indexed collection,
        uint256 indexed tokenId,
        address indexed seller,
        address buyer,
        uint256 price,
        uint256 fee,
        address feeRecipient,
        address paymentAsset,
        uint64 nonce
    );
    event TreasurySet(address indexed treasury);
    event FeeBpsSet(uint16 feeBps);

    function setUp() public {
        _deployAgentmarket();
    }

    // ------------------------------------------------------------ constructor

    function testConstructorRejectsZeroAddresses() public {
        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        new Agentmarket(address(0), address(nftRegistry), address(venue), address(treasury), DEFAULT_FEE_BPS);

        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        new Agentmarket(address(this), address(0), address(venue), address(treasury), DEFAULT_FEE_BPS);

        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        new Agentmarket(address(this), address(nftRegistry), address(0), address(treasury), DEFAULT_FEE_BPS);

        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        new Agentmarket(address(this), address(nftRegistry), address(venue), address(0), DEFAULT_FEE_BPS);
    }

    function testConstructorRejectsCodelessNFTRegistry() public {
        address codeless = address(0xC0DE);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.NotContract.selector, codeless));
        new Agentmarket(address(this), codeless, address(venue), address(treasury), DEFAULT_FEE_BPS);
    }

    function testConstructorRejectsCodelessVenueRegistry() public {
        address codeless = address(0xC0DE);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.NotContract.selector, codeless));
        new Agentmarket(address(this), address(nftRegistry), codeless, address(treasury), DEFAULT_FEE_BPS);
    }

    function testConstructorRejectsCodelessTreasury() public {
        address codeless = address(0xC0DE);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.NotContract.selector, codeless));
        new Agentmarket(address(this), address(nftRegistry), address(venue), codeless, DEFAULT_FEE_BPS);
    }

    function testConstructorRejectsTreasuryThatIsNotFeeRecipient() public {
        MockMarketTreasury inactiveTreasury = new MockMarketTreasury();
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.NotFeeRecipient.selector, address(inactiveTreasury)));
        new Agentmarket(address(this), address(nftRegistry), address(venue), address(inactiveTreasury), DEFAULT_FEE_BPS);
    }

    function testConstructorRejectsFeeAboveMax() public {
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.FeeAboveMax.selector, uint16(501), uint16(500)));
        new Agentmarket(address(this), address(nftRegistry), address(venue), address(treasury), 501);
    }

    function testConstructorStoresConfig() public view {
        assertEq(market.governance(), address(this));
        assertEq(market.pendingGovernance(), address(0));
        assertEq(market.nftRegistry(), address(nftRegistry));
        assertEq(market.venueRegistry(), address(venue));
        assertEq(market.treasury(), address(treasury));
        assertEq(market.feeBps(), DEFAULT_FEE_BPS);
        assertEq(market.maxFeeBps(), 500);
        assertEq(market.nonceOf(seller), 0);
    }

    // ------------------------------------------------------------------- list

    function testListStoresListingAndEmits() public {
        uint64 deadline = _deadline();

        vm.expectEmit(true, true, true, true, address(market));
        emit Listed(address(nft), 0, seller, DEFAULT_PRICE, DEFAULT_FEE_BPS, address(0), deadline, 1);

        vm.prank(seller);
        market.list(address(nft), DEFAULT_TOKEN_ID, DEFAULT_PRICE, deadline);

        IAgentmarket.Listing memory listing = market.listingOf(address(nft), DEFAULT_TOKEN_ID);
        assertEq(listing.order.seller, seller);
        assertEq(listing.order.collection, address(nft));
        assertEq(listing.order.tokenId, DEFAULT_TOKEN_ID);
        assertEq(listing.order.price, DEFAULT_PRICE);
        assertEq(listing.order.paymentAsset, address(0));
        assertEq(listing.order.deadline, deadline);
        assertEq(listing.order.nonce, 1);
        assertEq(listing.feeBps, DEFAULT_FEE_BPS);
        assertTrue(listing.active);

        assertEq(market.nonceOf(seller), 1);
        assertEq(nft.ownerOf(DEFAULT_TOKEN_ID), seller);
        assertEq(address(market).balance, 0);
    }

    function testListRejectsUnregisteredCollection() public {
        MockMarketNFT unregistered = new MockMarketNFT();
        unregistered.mint(seller, 0);

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.CollectionNotRegistered.selector, address(unregistered)));
        market.list(address(unregistered), 0, DEFAULT_PRICE, 0);
    }

    function testListRejectsNonOwner() public {
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(IAgentmarket.NotTokenOwner.selector, address(nft), DEFAULT_TOKEN_ID, buyer)
        );
        market.list(address(nft), DEFAULT_TOKEN_ID, DEFAULT_PRICE, 0);
    }

    function testListRejectsZeroPrice() public {
        vm.prank(seller);
        vm.expectRevert(IAgentmarket.ZeroPrice.selector);
        market.list(address(nft), DEFAULT_TOKEN_ID, 0, 0);
    }

    function testListRejectsPastOrCurrentDeadline() public {
        uint64 past = uint64(block.timestamp - 1);
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.InvalidDeadline.selector, past));
        market.list(address(nft), DEFAULT_TOKEN_ID, DEFAULT_PRICE, past);

        uint64 current = uint64(block.timestamp);
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.InvalidDeadline.selector, current));
        market.list(address(nft), DEFAULT_TOKEN_ID, DEFAULT_PRICE, current);
    }

    function testListAllowsZeroDeadline() public {
        vm.prank(seller);
        market.list(address(nft), DEFAULT_TOKEN_ID, DEFAULT_PRICE, 0);

        IAgentmarket.Listing memory listing = market.listingOf(address(nft), DEFAULT_TOKEN_ID);
        assertEq(listing.order.deadline, 0);
        assertTrue(listing.active);
    }

    function testListSameTokenOverwriteBySameSeller() public {
        _listDefault();

        uint64 deadline = _deadline();
        vm.expectEmit(true, true, true, true, address(market));
        emit Listed(address(nft), 0, seller, 2 ether, DEFAULT_FEE_BPS, address(0), deadline, 2);

        vm.prank(seller);
        market.list(address(nft), DEFAULT_TOKEN_ID, 2 ether, deadline);

        IAgentmarket.Listing memory listing = market.listingOf(address(nft), DEFAULT_TOKEN_ID);
        assertEq(listing.order.seller, seller);
        assertEq(listing.order.price, 2 ether);
        assertEq(listing.order.deadline, deadline);
        assertEq(listing.order.nonce, 2);
        assertTrue(listing.active);
        assertEq(market.nonceOf(seller), 2);
    }

    function testListSameTokenOverwriteByNewOwner() public {
        _listDefault();

        vm.prank(seller);
        nft.transferFrom(seller, other, DEFAULT_TOKEN_ID);
        assertEq(nft.ownerOf(DEFAULT_TOKEN_ID), other);

        vm.expectEmit(true, true, true, true, address(market));
        emit Listed(address(nft), 0, other, 2 ether, DEFAULT_FEE_BPS, address(0), 0, 1);

        vm.prank(other);
        market.list(address(nft), DEFAULT_TOKEN_ID, 2 ether, 0);

        IAgentmarket.Listing memory listing = market.listingOf(address(nft), DEFAULT_TOKEN_ID);
        assertEq(listing.order.seller, other);
        assertEq(listing.order.price, 2 ether);
        assertEq(listing.order.nonce, 1);
        assertTrue(listing.active);
        assertEq(market.nonceOf(seller), 1);
        assertEq(market.nonceOf(other), 1);
    }

    function testListDifferentTokenIdsAreIndependent() public {
        nft.mint(seller, 1);

        vm.prank(seller);
        market.list(address(nft), 0, 1 ether, 0);
        vm.prank(seller);
        market.list(address(nft), 1, 2 ether, 0);

        IAgentmarket.Listing memory first = market.listingOf(address(nft), 0);
        IAgentmarket.Listing memory second = market.listingOf(address(nft), 1);
        assertEq(first.order.price, 1 ether);
        assertEq(first.order.nonce, 1);
        assertEq(second.order.price, 2 ether);
        assertEq(second.order.nonce, 2);
        assertEq(market.nonceOf(seller), 2);

        vm.prank(seller);
        market.cancel(address(nft), 0);
        assertFalse(market.listingOf(address(nft), 0).active);
        assertTrue(market.listingOf(address(nft), 1).active);
    }

    // ----------------------------------------------------------------- cancel

    function testCancelClearsListingAndEmits() public {
        _listDefault();

        vm.expectEmit(true, true, true, true, address(market));
        emit Cancelled(address(nft), 0, seller);

        vm.prank(seller);
        market.cancel(address(nft), DEFAULT_TOKEN_ID);

        IAgentmarket.Listing memory listing = market.listingOf(address(nft), DEFAULT_TOKEN_ID);
        assertFalse(listing.active);
        assertEq(listing.order.seller, address(0));
        assertEq(listing.order.collection, address(0));
        assertEq(listing.order.tokenId, 0);
        assertEq(listing.order.price, 0);
        assertEq(listing.order.deadline, 0);
        assertEq(listing.order.nonce, 0);
        assertEq(listing.feeBps, 0);
        assertEq(market.nonceOf(seller), 1);
    }

    function testCancelRejectsNonSeller() public {
        _listDefault();

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.NotSeller.selector, address(nft), DEFAULT_TOKEN_ID, buyer));
        market.cancel(address(nft), DEFAULT_TOKEN_ID);
    }

    function testCancelRejectsInactiveListing() public {
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.ListingNotActive.selector, address(nft), DEFAULT_TOKEN_ID));
        market.cancel(address(nft), DEFAULT_TOKEN_ID);

        _listDefault();
        vm.prank(seller);
        market.cancel(address(nft), DEFAULT_TOKEN_ID);

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.ListingNotActive.selector, address(nft), DEFAULT_TOKEN_ID));
        market.cancel(address(nft), DEFAULT_TOKEN_ID);
    }

    // -------------------------------------------------------------------- buy

    function testBuySettlesAtomicallyAndEmits() public {
        _listDefault();
        _approveMarket(DEFAULT_TOKEN_ID);

        uint256 sellerBefore = seller.balance;
        uint256 treasuryBefore = address(treasury).balance;
        uint256 buyerBefore = buyer.balance;
        uint256 fee = (DEFAULT_PRICE * DEFAULT_FEE_BPS) / 10_000;

        vm.expectEmit(true, true, true, true, address(market));
        emit Sold(address(nft), 0, seller, buyer, DEFAULT_PRICE, fee, address(treasury), address(0), 1);

        vm.prank(buyer);
        market.buy{value: DEFAULT_PRICE}(address(nft), DEFAULT_TOKEN_ID);

        assertEq(nft.ownerOf(DEFAULT_TOKEN_ID), buyer);
        assertEq(seller.balance, sellerBefore + DEFAULT_PRICE - fee);
        assertEq(address(treasury).balance, treasuryBefore + fee);
        assertEq(buyer.balance, buyerBefore - DEFAULT_PRICE);
        assertEq(address(market).balance, 0);

        IAgentmarket.Listing memory listing = market.listingOf(address(nft), DEFAULT_TOKEN_ID);
        assertFalse(listing.active);
        assertEq(listing.order.seller, address(0));
        assertEq(listing.order.price, 0);
        assertEq(market.nonceOf(seller), 1);
    }

    function testBuyRejectsIncorrectPayment() public {
        _listDefault();

        uint256 underpayment = DEFAULT_PRICE - 1;
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.IncorrectPayment.selector, underpayment, DEFAULT_PRICE));
        market.buy{value: underpayment}(address(nft), DEFAULT_TOKEN_ID);

        uint256 overpayment = DEFAULT_PRICE + 1;
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.IncorrectPayment.selector, overpayment, DEFAULT_PRICE));
        market.buy{value: overpayment}(address(nft), DEFAULT_TOKEN_ID);

        assertTrue(market.listingOf(address(nft), DEFAULT_TOKEN_ID).active);
    }

    function testBuyRejectsSelfPurchase() public {
        _listDefault();
        vm.deal(seller, DEFAULT_PRICE);

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.SelfPurchase.selector, seller));
        market.buy{value: DEFAULT_PRICE}(address(nft), DEFAULT_TOKEN_ID);
    }

    function testBuyRejectsExpiredListing() public {
        uint64 deadline = _deadline();
        vm.prank(seller);
        market.list(address(nft), DEFAULT_TOKEN_ID, DEFAULT_PRICE, deadline);

        vm.warp(uint256(deadline) + 1);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.ListingExpired.selector, deadline));
        market.buy{value: DEFAULT_PRICE}(address(nft), DEFAULT_TOKEN_ID);
    }

    function testBuyAtExactDeadlineSucceeds() public {
        uint64 deadline = _deadline();
        vm.prank(seller);
        market.list(address(nft), DEFAULT_TOKEN_ID, DEFAULT_PRICE, deadline);
        _approveMarket(DEFAULT_TOKEN_ID);

        vm.warp(deadline);

        vm.prank(buyer);
        market.buy{value: DEFAULT_PRICE}(address(nft), DEFAULT_TOKEN_ID);
        assertEq(nft.ownerOf(DEFAULT_TOKEN_ID), buyer);
    }

    function testBuyRejectsInactiveListing() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.ListingNotActive.selector, address(nft), DEFAULT_TOKEN_ID));
        market.buy{value: DEFAULT_PRICE}(address(nft), DEFAULT_TOKEN_ID);
    }

    function testBuyRejectsWhenSellerNoLongerOwner() public {
        _listDefault();
        vm.prank(seller);
        nft.transferFrom(seller, other, DEFAULT_TOKEN_ID);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(IAgentmarket.SellerNoLongerOwner.selector, address(nft), DEFAULT_TOKEN_ID)
        );
        market.buy{value: DEFAULT_PRICE}(address(nft), DEFAULT_TOKEN_ID);
    }

    function testBuyWithZeroFeePaysSellerInFull() public {
        market.setFeeBps(0);
        _listDefault();
        _approveMarket(DEFAULT_TOKEN_ID);

        uint256 sellerBefore = seller.balance;
        uint256 treasuryBefore = address(treasury).balance;

        vm.expectEmit(true, true, true, true, address(market));
        emit Sold(address(nft), 0, seller, buyer, DEFAULT_PRICE, 0, address(treasury), address(0), 1);

        vm.prank(buyer);
        market.buy{value: DEFAULT_PRICE}(address(nft), DEFAULT_TOKEN_ID);

        assertEq(seller.balance, sellerBefore + DEFAULT_PRICE);
        assertEq(address(treasury).balance, treasuryBefore);
        assertEq(nft.ownerOf(DEFAULT_TOKEN_ID), buyer);
    }

    function testBuyRoundsFeeDown() public {
        uint256 price = 101;
        uint256 expectedFee = 1;

        vm.prank(seller);
        market.list(address(nft), DEFAULT_TOKEN_ID, price, 0);
        _approveMarket(DEFAULT_TOKEN_ID);

        vm.prank(buyer);
        market.buy{value: price}(address(nft), DEFAULT_TOKEN_ID);

        assertEq(seller.balance, price - expectedFee);
        assertEq(address(treasury).balance, expectedFee);
        assertEq(nft.ownerOf(DEFAULT_TOKEN_ID), buyer);
    }

    function testBuyUsesFeeSnapshotAfterGovernanceChange() public {
        _listDefault();
        market.setFeeBps(500);

        IAgentmarket.Listing memory listing = market.listingOf(address(nft), DEFAULT_TOKEN_ID);
        assertEq(listing.feeBps, DEFAULT_FEE_BPS);
        assertEq(market.feeBps(), 500);

        _approveMarket(DEFAULT_TOKEN_ID);
        uint256 fee = (DEFAULT_PRICE * DEFAULT_FEE_BPS) / 10_000;

        vm.expectEmit(true, true, true, true, address(market));
        emit Sold(address(nft), 0, seller, buyer, DEFAULT_PRICE, fee, address(treasury), address(0), 1);

        vm.prank(buyer);
        market.buy{value: DEFAULT_PRICE}(address(nft), DEFAULT_TOKEN_ID);

        assertEq(address(treasury).balance, fee);
        assertEq(seller.balance, DEFAULT_PRICE - fee);
    }

    function testTreasuryMigrationAppliesToPendingListing() public {
        _listDefault();

        MockMarketTreasury newTreasury = new MockMarketTreasury();
        venue.setFeeRecipient(address(newTreasury), true);

        vm.expectEmit(true, false, false, false, address(market));
        emit TreasurySet(address(newTreasury));
        market.setTreasury(address(newTreasury));
        assertEq(market.treasury(), address(newTreasury));

        _approveMarket(DEFAULT_TOKEN_ID);
        uint256 fee = (DEFAULT_PRICE * DEFAULT_FEE_BPS) / 10_000;

        vm.prank(buyer);
        market.buy{value: DEFAULT_PRICE}(address(nft), DEFAULT_TOKEN_ID);

        assertEq(address(newTreasury).balance, fee);
        assertEq(address(treasury).balance, 0);
    }

    // -------------------------------------------------------------- fee config

    function testSetFeeBpsRejectsNonGovernance() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, other));
        market.setFeeBps(200);
    }

    function testSetFeeBpsRejectsAboveMax() public {
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.FeeAboveMax.selector, uint16(501), uint16(500)));
        market.setFeeBps(501);
    }

    function testSetFeeBpsAllowsMaxAndEmits() public {
        vm.expectEmit(false, false, false, true, address(market));
        emit FeeBpsSet(500);
        market.setFeeBps(500);

        assertEq(market.feeBps(), 500);
    }

    // ---------------------------------------------------------- treasury config

    function testSetTreasuryRejectsNonGovernance() public {
        MockMarketTreasury newTreasury = new MockMarketTreasury();
        venue.setFeeRecipient(address(newTreasury), true);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, other));
        market.setTreasury(address(newTreasury));
    }

    function testSetTreasuryRejectsInactiveFeeRecipient() public {
        MockMarketTreasury inactiveTreasury = new MockMarketTreasury();
        venue.setFeeRecipient(address(inactiveTreasury), true);
        venue.setFeeRecipient(address(inactiveTreasury), false);

        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.NotFeeRecipient.selector, address(inactiveTreasury)));
        market.setTreasury(address(inactiveTreasury));
    }

    function testSetTreasuryRejectsZeroOrCodelessAddress() public {
        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        market.setTreasury(address(0));

        address codeless = address(0xC0DE);
        vm.expectRevert(abi.encodeWithSelector(IAgentmarket.NotContract.selector, codeless));
        market.setTreasury(codeless);
    }

    // ----------------------------------------------------------- isExecutable

    function testIsExecutableTrueWhenActiveAndApproved() public {
        _listDefault();
        assertFalse(market.isExecutable(address(nft), DEFAULT_TOKEN_ID));

        _approveMarket(DEFAULT_TOKEN_ID);
        assertTrue(market.isExecutable(address(nft), DEFAULT_TOKEN_ID));
    }

    function testIsExecutableTrueWithOperatorApproval() public {
        _listDefault();

        vm.prank(seller);
        nft.setApprovalForAll(address(market), true);

        assertTrue(market.isExecutable(address(nft), DEFAULT_TOKEN_ID));
    }

    function testIsExecutableFalseWhenInactive() public {
        assertFalse(market.isExecutable(address(nft), DEFAULT_TOKEN_ID));

        _listDefault();
        _approveMarket(DEFAULT_TOKEN_ID);
        assertTrue(market.isExecutable(address(nft), DEFAULT_TOKEN_ID));

        vm.prank(seller);
        market.cancel(address(nft), DEFAULT_TOKEN_ID);
        assertFalse(market.isExecutable(address(nft), DEFAULT_TOKEN_ID));
    }

    function testIsExecutableFalseWhenExpired() public {
        uint64 deadline = _deadline();
        vm.prank(seller);
        market.list(address(nft), DEFAULT_TOKEN_ID, DEFAULT_PRICE, deadline);
        _approveMarket(DEFAULT_TOKEN_ID);

        vm.warp(uint256(deadline) + 1);
        assertFalse(market.isExecutable(address(nft), DEFAULT_TOKEN_ID));
    }

    function testIsExecutableFalseWhenOwnerTransferred() public {
        _listDefault();
        _approveMarket(DEFAULT_TOKEN_ID);

        vm.prank(seller);
        nft.transferFrom(seller, other, DEFAULT_TOKEN_ID);

        assertFalse(market.isExecutable(address(nft), DEFAULT_TOKEN_ID));
    }

    // --------------------------------------------------------------- reentrancy

    function testBuyRejectsReentrantSeller() public {
        ReentrantSeller reentrantSeller = new ReentrantSeller(market, nft, 1);
        nft.mint(address(reentrantSeller), 1);
        reentrantSeller.list(DEFAULT_PRICE);

        vm.prank(buyer);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        market.buy{value: DEFAULT_PRICE}(address(nft), 1);

        assertEq(nft.ownerOf(1), address(reentrantSeller));
        assertTrue(market.listingOf(address(nft), 1).active);
    }

    // ------------------------------------------------------------ native guard

    function testMarketRejectsDirectBNB() public {
        vm.deal(other, 1);
        vm.prank(other);
        (bool success,) = address(market).call{value: 1}("");

        assertFalse(success);
        assertEq(address(market).balance, 0);
    }
}

/// @dev Seller contract whose BNB receive callback re-enters `buy`.
contract ReentrantSeller {
    Agentmarket private immutable _market;
    MockMarketNFT private immutable _nft;
    uint256 private immutable _tokenId;

    constructor(Agentmarket market_, MockMarketNFT nft_, uint256 tokenId_) {
        _market = market_;
        _nft = nft_;
        _tokenId = tokenId_;
    }

    function list(uint256 price) external {
        _nft.approve(address(_market), _tokenId);
        _market.list(address(_nft), _tokenId, price, 0);
    }

    receive() external payable {
        _market.buy{value: msg.value}(address(_nft), _tokenId);
    }
}
