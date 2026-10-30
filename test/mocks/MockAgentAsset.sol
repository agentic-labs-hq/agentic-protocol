// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssetType} from "../../contracts/common/Types.sol";
import {IAssetRegistry} from "../../contracts/interfaces/IAssetRegistry.sol";

/// @notice Arbitrary gated-asset shape used to exercise `AgenticAssetRegistry` stamps.
/// @dev When `factory` is this contract the asset is itself an asset registrar
/// and `registerOn` calls the registry with `msg.sender == factory`.
contract MockAgentAsset {
    address public factory;
    address public policy;
    address public creator;
    AssetType internal _assetType;

    constructor(address factory_, address policy_, address creator_, AssetType assetType_) {
        // `address(0)` means "this asset is its own factory stamp", which lets a
        // test asset be its own registrar (`msg.sender == factory`).
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
        IAssetRegistry(registry).registerAsset(address(this), policy_, creator_);
    }
}

/// @notice Generic asset/pool registrar used to reach registry validation paths
/// that the real factory never produces (zero/codeless asset, wrong stamps).
contract MockAssetRegistrar {
    function register(address registry, address asset, address policy, address creator) external {
        IAssetRegistry(registry).registerAsset(asset, policy, creator);
    }

    function record(address registry, address asset, address pool) external {
        IAssetRegistry(registry).recordPool(asset, pool);
    }
}
