// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {Agentmarket} from "../../contracts/market/Agentmarket.sol";

import {MockMarketNFT} from "../mocks/MockMarketNFT.sol";
import {MockMarketTreasury} from "../mocks/MockMarketTreasury.sol";
import {MockMarketVenue} from "../mocks/MockMarketVenue.sol";
import {MockNFTRegistry} from "../mocks/MockNFTRegistry.sol";

/// @notice Shared Agentmarket fixture: mock registry/venue/treasury, the market
/// itself and one registered `MockMarketNFT` collection with token 0 minted to
/// `seller`.
abstract contract AgentmarketFixture is Test {
    uint256 internal constant DEFAULT_PRICE = 1 ether;
    uint16 internal constant DEFAULT_FEE_BPS = 100;
    uint256 internal constant BUYER_BALANCE = 100 ether;
    uint256 internal constant DEFAULT_TOKEN_ID = 0;
    uint256 internal constant START_TIMESTAMP = 1_000_000;

    MockNFTRegistry internal nftRegistry;
    MockMarketVenue internal venue;
    MockMarketTreasury internal treasury;
    Agentmarket internal market;
    MockMarketNFT internal nft;

    address internal seller = address(0xA11CE);
    address internal buyer = address(0xB0B);
    address internal other = address(0xCAFE);

    function _deployAgentmarket() internal {
        vm.warp(START_TIMESTAMP);

        nftRegistry = new MockNFTRegistry();
        venue = new MockMarketVenue();
        treasury = new MockMarketTreasury();
        venue.setFeeRecipient(address(treasury), true);

        market =
            new Agentmarket(address(this), address(nftRegistry), address(venue), address(treasury), DEFAULT_FEE_BPS);

        nft = new MockMarketNFT();
        nftRegistry.setRegistered(address(nft), true);
        nft.mint(seller, DEFAULT_TOKEN_ID);
        vm.deal(buyer, BUYER_BALANCE);
    }

    /// @dev List token 0 by `seller` at `DEFAULT_PRICE` with no expiry.
    function _listDefault() internal returns (uint64 nonce) {
        vm.prank(seller);
        market.list(address(nft), DEFAULT_TOKEN_ID, DEFAULT_PRICE, 0);
        nonce = market.nonceOf(seller);
    }

    function _approveMarket(uint256 tokenId) internal {
        vm.prank(seller);
        nft.approve(address(market), tokenId);
    }

    function _deadline() internal view returns (uint64) {
        return uint64(block.timestamp + 1 days);
    }
}
