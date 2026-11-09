// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {IAgentAsset} from "./IAgentAsset.sol";

/// @notice Optional immutable metadata resolver for a gated NFT collection.
/// @dev The resolver is chosen at collection creation and can never change.
/// Returning metadata from an external contract keeps the protocol free of
/// per-token storage while still covering UGC, reveals and on-chain art.
interface INFTMetadataResolver {
    function tokenURI(address collection, uint256 tokenId) external view returns (string memory);
}

/// @notice Gated NFT collection surface (INTERFACES v2.3 §NFT).
interface IAgentNFT is IAgentAsset, IERC721Metadata {
    function factory() external view returns (address);
    function maxSupply() external view returns (uint256);
    function totalMinted() external view returns (uint256);
    function baseURI() external view returns (string memory);
    function metadataResolver() external view returns (address);

    function mint(address to, uint256 count) external;
    function mintBatch(address[] calldata recipients, uint256[] calldata counts) external;

    event Minted(address indexed to, uint256 firstTokenId, uint256 count);
}
