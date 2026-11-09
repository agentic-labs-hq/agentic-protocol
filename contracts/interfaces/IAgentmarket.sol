// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGovernance} from "./IGovernance.sol";

/// @notice Agentmarket: non-custodial NFT marketplace (venue layer).
/// @dev Orders are approval-based. The market never holds the NFT or the
/// payment. V1 settles in native BNB only; `paymentAsset` is reserved.
interface IAgentmarket is IGovernance {
    /// @notice EIP-712 compatible listing order. V1 stores it on chain and does
    /// not verify signatures; a future signed-order entry point reuses it.
    struct Order {
        address seller;
        address collection;
        uint256 tokenId;
        uint256 price;
        address paymentAsset; // address(0) = native BNB
        uint64 deadline; // 0 = no expiry
        uint64 nonce; // per-seller, monotonic
    }

    /// @notice Stored listing: the order plus market metadata.
    struct Listing {
        Order order;
        uint16 feeBps; // snapshot at list time
        bool active;
    }

    /// @notice Thrown when a required address has no code.
    error NotContract(address account);
    /// @notice Thrown when the treasury is not an active `FEE_RECIPIENT`.
    error NotFeeRecipient(address account);
    /// @notice Thrown when a fee exceeds the hard cap.
    error FeeAboveMax(uint16 feeBps, uint16 maxFeeBps);
    /// @notice Thrown when the collection is not registered in the NFT registry.
    error CollectionNotRegistered(address collection);
    /// @notice Thrown when the caller is not the token owner.
    error NotTokenOwner(address collection, uint256 tokenId, address caller);
    /// @notice Thrown when the price is zero.
    error ZeroPrice();
    /// @notice Thrown when the deadline is in the past at list time.
    error InvalidDeadline(uint64 deadline);
    /// @notice Thrown when the listing is not active.
    error ListingNotActive(address collection, uint256 tokenId);
    /// @notice Thrown when the caller is not the listing seller.
    error NotSeller(address collection, uint256 tokenId, address caller);
    /// @notice Thrown when the payment does not equal the listing price.
    error IncorrectPayment(uint256 sent, uint256 price);
    /// @notice Thrown when the seller tries to buy their own listing.
    error SelfPurchase(address seller);
    /// @notice Thrown when the listing deadline has passed.
    error ListingExpired(uint64 deadline);
    /// @notice Thrown for a payment asset other than native BNB in V1.
    error UnsupportedPaymentAsset(address paymentAsset);
    /// @notice Thrown when the seller no longer owns the token.
    error SellerNoLongerOwner(address collection, uint256 tokenId);

    function nftRegistry() external view returns (address);
    function venueRegistry() external view returns (address);
    function treasury() external view returns (address);
    function feeBps() external view returns (uint16);
    function maxFeeBps() external pure returns (uint16);
    function nonceOf(address seller) external view returns (uint64);
    function listingOf(address collection, uint256 tokenId) external view returns (Listing memory);
    function isExecutable(address collection, uint256 tokenId) external view returns (bool);

    function list(address collection, uint256 tokenId, uint256 price, uint64 deadline) external;
    function cancel(address collection, uint256 tokenId) external;
    function buy(address collection, uint256 tokenId) external payable;
    function setTreasury(address newTreasury) external;
    function setFeeBps(uint16 newFeeBps) external;

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
}
