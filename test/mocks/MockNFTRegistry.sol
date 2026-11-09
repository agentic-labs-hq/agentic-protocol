// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {INFTRegistry} from "../../contracts/interfaces/INFTRegistry.sol";

/// @notice Minimal `INFTRegistry` test double.
/// @dev Only `isRegistered` is used by the NFT facility templates. The registry
/// is provenance-only (never in the transfer path), so every other method is
/// either a default view or an explicit revert.
contract MockNFTRegistry is INFTRegistry {
    mapping(address => bool) private _registered;

    /// @notice Thrown by methods the fixture does not exercise.
    error NotSupported();

    /// @notice Test hook: mark a collection as gated (or not).
    function setRegistered(address nft, bool registered) external {
        _registered[nft] = registered;
    }

    /// @inheritdoc INFTRegistry
    function isRegistered(address nft) external view override returns (bool) {
        return _registered[nft];
    }

    /// @inheritdoc INFTRegistry
    function policyRegistry() external pure override returns (address) {
        return address(0);
    }

    /// @inheritdoc INFTRegistry
    function policyOf(address) external pure override returns (address) {
        return address(0);
    }

    /// @inheritdoc INFTRegistry
    function creatorOf(address) external pure override returns (address) {
        return address(0);
    }

    /// @inheritdoc INFTRegistry
    function isRegistrar(address) external pure override returns (bool) {
        return false;
    }

    /// @inheritdoc INFTRegistry
    /// @dev Test shortcut that registers without provenance checks.
    function registerAsset(address nft, address, address) external override {
        _registered[nft] = true;
        emit AssetRegistered(nft, address(0), address(0));
    }

    /// @inheritdoc INFTRegistry
    function setRegistrar(address, bool) external pure override {
        revert NotSupported();
    }
}
