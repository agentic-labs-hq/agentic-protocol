// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {FacilityCategory} from "../common/Types.sol";
import {Governance2Step} from "../common/Governance2Step.sol";
import {IAgentmarket} from "../interfaces/IAgentmarket.sol";
import {INFTRegistry} from "../interfaces/INFTRegistry.sol";
import {IVenueRegistry} from "../interfaces/IVenueRegistry.sol";

/// @notice Agentmarket: non-custodial, approval-based NFT marketplace
/// (venue layer). It never holds the NFT or the payment.
/// @dev Listing storage is keyed by `(collection, tokenId)`; a token has at
/// most one listing. `buy` deletes the listing before any external call, then
/// transfers the NFT and pays the seller and the treasury atomically. The fee
/// is snapshotted at list time; the treasury is read at settlement so a
/// governance treasury migration applies to pending listings, matching
/// Agentswap. V1 supports native BNB only.
contract Agentmarket is IAgentmarket, Governance2Step, ReentrancyGuard {
    /// @notice Hard fee cap. Immutable behavior: `setFeeBps` can never exceed it.
    uint16 private constant _MAX_FEE_BPS = 500;
    /// @notice Fee denominator (basis points).
    uint256 private constant _FEE_DENOMINATOR = 10_000;

    /// @inheritdoc IAgentmarket
    address public immutable override nftRegistry;

    /// @inheritdoc IAgentmarket
    address public immutable override venueRegistry;

    /// @inheritdoc IAgentmarket
    address public override treasury;

    /// @inheritdoc IAgentmarket
    uint16 public override feeBps;

    /// @inheritdoc IAgentmarket
    mapping(address => uint64) public override nonceOf;

    mapping(address => mapping(uint256 => Listing)) private _listings;

    /// @param governance_ Two-step governance (the protocol Safe).
    /// @param nftRegistry_ Gated NFT registry used for collection provenance.
    /// @param venueRegistry_ Venue registry used to validate the treasury.
    /// @param treasury_ Initial active `FEE_RECIPIENT` receiving the fee.
    /// @param initialFeeBps_ Initial fee in basis points (<= 500).
    constructor(
        address governance_,
        address nftRegistry_,
        address venueRegistry_,
        address treasury_,
        uint16 initialFeeBps_
    ) Governance2Step(governance_) {
        if (nftRegistry_ == address(0) || venueRegistry_ == address(0) || treasury_ == address(0)) {
            revert ZeroAddress();
        }
        if (nftRegistry_.code.length == 0) revert NotContract(nftRegistry_);
        if (venueRegistry_.code.length == 0) revert NotContract(venueRegistry_);
        if (treasury_.code.length == 0) revert NotContract(treasury_);
        if (!IVenueRegistry(venueRegistry_).isFacilityOfCategory(treasury_, FacilityCategory.FEE_RECIPIENT)) {
            revert NotFeeRecipient(treasury_);
        }
        if (initialFeeBps_ > _MAX_FEE_BPS) revert FeeAboveMax(initialFeeBps_, _MAX_FEE_BPS);

        nftRegistry = nftRegistry_;
        venueRegistry = venueRegistry_;
        treasury = treasury_;
        feeBps = initialFeeBps_;
    }

    /// @inheritdoc IAgentmarket
    function maxFeeBps() external pure override returns (uint16) {
        return _MAX_FEE_BPS;
    }

    /// @inheritdoc IAgentmarket
    function listingOf(address collection, uint256 tokenId) external view override returns (Listing memory) {
        return _listings[collection][tokenId];
    }

    /// @inheritdoc IAgentmarket
    /// @dev Read-only convenience for buyers and tooling. It cannot close the
    /// race between the check and `buy`; the settlement checks remain final.
    function isExecutable(address collection, uint256 tokenId) external view override returns (bool) {
        Listing storage listing = _listings[collection][tokenId];
        if (!listing.active) return false;
        if (listing.order.paymentAsset != address(0)) return false;
        // forge-lint: disable-next-line(block-timestamp)
        if (listing.order.deadline != 0 && block.timestamp > listing.order.deadline) return false;

        IERC721 nft = IERC721(collection);
        if (nft.ownerOf(tokenId) != listing.order.seller) return false;
        if (nft.getApproved(tokenId) != address(this) && !nft.isApprovedForAll(listing.order.seller, address(this))) {
            return false;
        }
        return true;
    }

    /// @inheritdoc IAgentmarket
    /// @dev The collection must be registered and the caller must own the
    /// token. Re-listing overwrites the single listing for that token id.
    function list(address collection, uint256 tokenId, uint256 price, uint64 deadline) external override {
        if (!INFTRegistry(nftRegistry).isRegistered(collection)) revert CollectionNotRegistered(collection);
        if (price == 0) revert ZeroPrice();
        // forge-lint: disable-next-line(block-timestamp)
        if (deadline != 0 && deadline <= block.timestamp) revert InvalidDeadline(deadline);
        if (IERC721(collection).ownerOf(tokenId) != msg.sender) {
            revert NotTokenOwner(collection, tokenId, msg.sender);
        }

        uint64 nonce = ++nonceOf[msg.sender];
        uint16 snapshot = feeBps;
        _listings[collection][tokenId] = Listing({
            order: Order({
                seller: msg.sender,
                collection: collection,
                tokenId: tokenId,
                price: price,
                paymentAsset: address(0),
                deadline: deadline,
                nonce: nonce
            }),
            feeBps: snapshot,
            active: true
        });

        emit Listed(collection, tokenId, msg.sender, price, snapshot, address(0), deadline, nonce);
    }

    /// @inheritdoc IAgentmarket
    function cancel(address collection, uint256 tokenId) external override {
        Listing storage listing = _listings[collection][tokenId];
        if (!listing.active) revert ListingNotActive(collection, tokenId);
        if (listing.order.seller != msg.sender) revert NotSeller(collection, tokenId, msg.sender);

        delete _listings[collection][tokenId];
        emit Cancelled(collection, tokenId, msg.sender);
    }

    /// @inheritdoc IAgentmarket
    /// @dev Atomic settlement: delete listing, transfer NFT, pay seller, pay
    /// fee. Any failure reverts the whole call.
    function buy(address collection, uint256 tokenId) external payable override nonReentrant {
        Listing storage listing = _listings[collection][tokenId];
        if (!listing.active) revert ListingNotActive(collection, tokenId);

        Order memory order = listing.order;
        uint16 snapshot = listing.feeBps;

        if (msg.value != order.price) revert IncorrectPayment(msg.value, order.price);
        if (msg.sender == order.seller) revert SelfPurchase(order.seller);
        // forge-lint: disable-next-line(block-timestamp)
        if (order.deadline != 0 && block.timestamp > order.deadline) revert ListingExpired(order.deadline);
        if (order.paymentAsset != address(0)) revert UnsupportedPaymentAsset(order.paymentAsset);
        if (IERC721(collection).ownerOf(tokenId) != order.seller) revert SellerNoLongerOwner(collection, tokenId);

        // Effects before interactions.
        delete _listings[collection][tokenId];
        address feeRecipient = treasury;

        IERC721(collection).transferFrom(order.seller, msg.sender, tokenId);

        uint256 fee = (order.price * snapshot) / _FEE_DENOMINATOR;
        uint256 sellerAmount = order.price - fee;
        Address.sendValue(payable(order.seller), sellerAmount);
        if (fee != 0) Address.sendValue(payable(feeRecipient), fee);

        emit Sold(
            collection,
            tokenId,
            order.seller,
            msg.sender,
            order.price,
            fee,
            feeRecipient,
            order.paymentAsset,
            order.nonce
        );
    }

    /// @inheritdoc IAgentmarket
    function setTreasury(address newTreasury) external override onlyGovernance {
        if (newTreasury == address(0)) revert ZeroAddress();
        if (newTreasury.code.length == 0) revert NotContract(newTreasury);
        if (!IVenueRegistry(venueRegistry).isFacilityOfCategory(newTreasury, FacilityCategory.FEE_RECIPIENT)) {
            revert NotFeeRecipient(newTreasury);
        }

        treasury = newTreasury;
        emit TreasurySet(newTreasury);
    }

    /// @inheritdoc IAgentmarket
    function setFeeBps(uint16 newFeeBps) external override onlyGovernance {
        if (newFeeBps > _MAX_FEE_BPS) revert FeeAboveMax(newFeeBps, _MAX_FEE_BPS);
        feeBps = newFeeBps;
        emit FeeBpsSet(newFeeBps);
    }
}
