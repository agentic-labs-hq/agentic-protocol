// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {AssetType, TransferKind} from "../common/Types.sol";
import {IAgentAsset} from "../interfaces/IAgentAsset.sol";
import {IAgentNFT, INFTMetadataResolver} from "../interfaces/IAgentNFT.sol";
import {ITransferPolicy} from "../interfaces/ITransferPolicy.sol";

/// @notice Gated NFT collection for a single policy version (INTERFACES v2.3 §NFT).
/// @dev Deployed only by `AgenticNFTFactory`. Supply is capped at
/// `maxSupply` and minted lazily by the immutable `creator`; there is no burn,
/// pause, admin or proxy path. Every `_update` (mint, transfer and
/// transferFrom) asks the immutable `ITransferPolicy` and reverts on denial.
///
/// Metadata has exactly two immutable modes chosen at creation: `baseURI` +
/// tokenId, or an external `INFTMetadataResolver`. The contract stores no
/// per-token URI. `metadataURI` and `baseURI` are write-once storage because
/// solc 0.8.20 only permits value types as immutable.
contract AgenticNFT is ERC721, IAgentNFT {
    using Strings for uint256;

    /// @notice Thrown when anyone other than the declared factory constructs the collection.
    error NotFactory(address caller);
    /// @notice Thrown when the transfer policy denies a mint/transfer.
    error TransferDenied(bytes32 reason);
    /// @notice Thrown for a zero policy or creator address.
    error InvalidConfiguration();
    /// @notice Thrown when `maxSupply` is zero.
    error ZeroSupply();
    /// @notice Thrown when a mint would exceed `maxSupply`.
    error InvalidSupply(uint256 requested, uint256 remaining);
    /// @notice Thrown when the recipient and count arrays differ in length.
    error LengthMismatch();
    /// @notice Thrown when a mint requests zero tokens.
    error ZeroCount();
    /// @notice Thrown when the caller is not the creator.
    error NotCreator(address caller);

    /// @inheritdoc IAgentNFT
    address public immutable override factory;

    /// @inheritdoc IAgentAsset
    address public immutable override policy;

    /// @inheritdoc IAgentAsset
    address public immutable override creator;

    /// @inheritdoc IAgentNFT
    uint256 public immutable override maxSupply;

    /// @inheritdoc IAgentNFT
    address public immutable override metadataResolver;

    /// @inheritdoc IAgentNFT
    uint256 public override totalMinted;

    string private _baseURIValue;
    string private _metadataURIValue;

    /// @param name_ ERC-721 name.
    /// @param symbol_ ERC-721 symbol.
    /// @param factory_ The only address allowed to deploy; must be `msg.sender`.
    /// @param policy_ Immutable transfer policy version selected for this collection.
    /// @param creator_ The factory caller recorded as creator and sole minter.
    /// @param maxSupply_ Fixed cap; minting stops when `totalMinted` reaches it.
    /// @param baseURI_ Metadata prefix used when `metadataResolver` is zero.
    /// @param metadataURI_ Collection-level metadata URI; write-once.
    /// @param metadataResolver_ Optional resolver contract; zero selects `baseURI`.
    constructor(
        string memory name_,
        string memory symbol_,
        address factory_,
        address policy_,
        address creator_,
        uint256 maxSupply_,
        string memory baseURI_,
        string memory metadataURI_,
        address metadataResolver_
    ) ERC721(name_, symbol_) {
        if (msg.sender != factory_) revert NotFactory(msg.sender);
        if (policy_ == address(0) || creator_ == address(0)) revert InvalidConfiguration();
        if (maxSupply_ == 0) revert ZeroSupply();

        factory = factory_;
        policy = policy_;
        creator = creator_;
        maxSupply = maxSupply_;
        metadataResolver = metadataResolver_;
        _baseURIValue = baseURI_;
        _metadataURIValue = metadataURI_;
    }

    modifier onlyCreator() {
        if (msg.sender != creator) revert NotCreator(msg.sender);
        _;
    }

    /// @inheritdoc IAgentAsset
    function assetType() external pure override returns (AssetType) {
        return AssetType.NFT;
    }

    /// @inheritdoc IAgentNFT
    function baseURI() external view override returns (string memory) {
        return _baseURIValue;
    }

    /// @inheritdoc IAgentAsset
    function metadataURI() external view override returns (string memory) {
        return _metadataURIValue;
    }

    /// @inheritdoc IAgentNFT
    function mint(address to, uint256 count) external override onlyCreator {
        if (count == 0) revert ZeroCount();
        uint256 first = _reserve(count);
        _mintRange(to, first, count);
    }

    /// @inheritdoc IAgentNFT
    /// @dev `counts[i]` tokens are minted consecutively to `recipients[i]`.
    /// Zero-count entries are skipped without emitting an event.
    function mintBatch(address[] calldata recipients, uint256[] calldata counts) external override onlyCreator {
        uint256 length = recipients.length;
        if (length != counts.length) revert LengthMismatch();

        uint256 total;
        for (uint256 i; i < length; ++i) {
            total += counts[i];
        }
        if (total == 0) revert ZeroCount();

        uint256 next = _reserve(total);
        for (uint256 i; i < length; ++i) {
            uint256 count = counts[i];
            if (count == 0) continue;
            _mintRange(recipients[i], next, count);
            next += count;
        }
    }

    /// @inheritdoc ERC721
    function tokenURI(uint256 tokenId) public view override(ERC721, IERC721Metadata) returns (string memory) {
        _requireOwned(tokenId);
        address resolver = metadataResolver;
        if (resolver != address(0)) {
            return INFTMetadataResolver(resolver).tokenURI(address(this), tokenId);
        }
        return string.concat(_baseURIValue, tokenId.toString());
    }

    /// @dev Gate every ownership movement, including mint, through the
    /// immutable policy. The operator is the caller (`_msgSender()`) and the
    /// context is exactly `abi.encode(TransferKind.TRANSFER)`.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        (bool allowed, bytes32 reason) = ITransferPolicy(policy)
            .canTransfer(address(this), from, to, _msgSender(), abi.encode(TransferKind.TRANSFER));
        if (!allowed) revert TransferDenied(reason);
        return super._update(to, tokenId, auth);
    }

    /// @dev Reserve `count` token ids and return the first one.
    function _reserve(uint256 count) private returns (uint256 first) {
        uint256 remaining = maxSupply - totalMinted;
        if (count > remaining) revert InvalidSupply(count, remaining);
        first = totalMinted;
        totalMinted = first + count;
    }

    /// @dev Mint a consecutive id range and emit one event for it.
    function _mintRange(address to, uint256 first, uint256 count) private {
        for (uint256 i; i < count; ++i) {
            _mint(to, first + i);
        }
        emit Minted(to, first, count);
    }
}
