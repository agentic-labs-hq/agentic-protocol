// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Gated NFT collection registry (INTERFACES v2.3 §NFT).
/// @dev Provenance only. It is never in the transfer path: the collection's
/// policy alone decides eligibility. Unlike the FT asset registry there is no
/// pool surface, because NFT collections have no pools.
interface INFTRegistry {
    function policyRegistry() external view returns (address);
    function isRegistered(address nft) external view returns (bool);
    function policyOf(address nft) external view returns (address);
    function creatorOf(address nft) external view returns (address);
    function isRegistrar(address account) external view returns (bool);

    function registerAsset(address nft, address policy, address creator) external;
    function setRegistrar(address account, bool enabled) external;

    event AssetRegistered(address indexed nft, address indexed policy, address indexed creator);
    event RegistrarSet(address indexed account, bool enabled);
}
