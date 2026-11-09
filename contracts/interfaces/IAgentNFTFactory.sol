// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Permissionless gated NFT collection factory interface (INTERFACES v2.3 §NFT).
interface IAgentNFTFactory {
    function policyRegistry() external view returns (address);
    function assetRegistry() external view returns (address);

    function createCollection(
        string calldata name,
        string calldata symbol,
        address policy,
        uint256 maxSupply,
        string calldata baseURI,
        string calldata metadataURI,
        address metadataResolver
    ) external returns (address nft);

    event CollectionCreated(
        address indexed nft,
        address indexed creator,
        address indexed policy,
        uint256 maxSupply,
        address metadataResolver
    );
}
