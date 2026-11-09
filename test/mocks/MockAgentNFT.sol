// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssetType} from "../../contracts/common/Types.sol";
import {INFTRegistry} from "../../contracts/interfaces/INFTRegistry.sol";

/// @notice Arbitrary gated-NFT shape used to exercise `AgenticNFTRegistry` stamps.
/// @dev When `factory` is this contract the NFT is itself a registrar and
/// `registerOn` calls the registry with `msg.sender == factory`.
contract MockAgentNFT {
    address public factory;
    address public policy;
    address public creator;
    AssetType internal _assetType;

    constructor(address factory_, address policy_, address creator_, AssetType assetType_) {
        // `address(0)` means "this collection is its own factory stamp", which
        // lets a test collection be its own registrar (`msg.sender == factory`).
        factory = factory_ == address(0) ? address(this) : factory_;
        policy = policy_;
        creator = creator_;
        _assetType = assetType_;
    }

    function assetType() external view returns (AssetType) {
        return _assetType;
    }

    function metadataURI() external pure returns (string memory) {
        return "";
    }

    function registerOn(address registry, address policy_, address creator_) external {
        INFTRegistry(registry).registerAsset(address(this), policy_, creator_);
    }
}

/// @notice Generic NFT registrar used to reach registry validation paths that
/// the real factory never produces (zero/codeless collection, wrong stamps).
contract MockNFTRegistrar {
    function register(address registry, address nft, address policy, address creator) external {
        INFTRegistry(registry).registerAsset(nft, policy, creator);
    }
}
