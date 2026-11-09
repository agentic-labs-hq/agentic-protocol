// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAgentNFTFactory} from "../interfaces/IAgentNFTFactory.sol";
import {INFTRegistry} from "../interfaces/INFTRegistry.sol";
import {IPolicyRegistry} from "../interfaces/IPolicyRegistry.sol";
import {AgenticNFT} from "./AgenticNFT.sol";

/// @notice Permissionless gated NFT collection factory (INTERFACES v2.3 §NFT).
/// @dev The caller needs no Agent ID: an agent or a project can create a
/// collection and becomes its immutable creator. The factory only deploys
/// `AgenticNFT` contracts, registers the collection in `AgenticNFTRegistry`,
/// and then has no further role: there is no admin mint, pause, upgrade or
/// proxy. Collections are free to create; there is no permit and no fee.
contract AgenticNFTFactory is IAgentNFTFactory {
    /// @inheritdoc IAgentNFTFactory
    address public immutable override policyRegistry;

    /// @inheritdoc IAgentNFTFactory
    address public immutable override assetRegistry;

    /// @notice Thrown when a registry/zero address argument is invalid.
    error ZeroRegistry();
    /// @notice Thrown when a configured address is not a contract.
    error RegistryHasNoCode(address registry);
    /// @notice Thrown when the policy is not registered/allowed.
    error PolicyNotAllowed(address policy);
    /// @notice Thrown when `maxSupply` is zero.
    error ZeroSupply();
    /// @notice Thrown when a non-zero metadata resolver has no code.
    error ResolverHasNoCode(address resolver);

    /// @dev Creation arguments decoded from `msg.data[4:]`. The field order and
    /// types exactly mirror the frozen seven-parameter ABI tuple, so the
    /// external selector is unchanged.
    struct CreateCollectionParams {
        string name;
        string symbol;
        address policy;
        uint256 maxSupply;
        string baseURI;
        string metadataURI;
        address metadataResolver;
    }

    /// @param policyRegistry_ Versioned policy registry.
    /// @param nftRegistry_ NFT registry that records created collections.
    constructor(address policyRegistry_, address nftRegistry_) {
        if (policyRegistry_ == address(0) || nftRegistry_ == address(0)) revert ZeroRegistry();
        if (policyRegistry_.code.length == 0 || nftRegistry_.code.length == 0) {
            revert RegistryHasNoCode(policyRegistry_.code.length == 0 ? policyRegistry_ : nftRegistry_);
        }

        policyRegistry = policyRegistry_;
        assetRegistry = nftRegistry_;
    }

    /// @inheritdoc IAgentNFTFactory
    /// @dev `policy == address(0)` resolves to `currentPolicy()`. Explicit
    /// policies must be registered and not deprecated. The collection is
    /// deployed with `msg.sender` as creator and then registered; any failure
    /// reverts the whole creation.
    function createCollection(
        string calldata,
        string calldata,
        address,
        uint256,
        string calldata,
        string calldata,
        address
    ) external override returns (address nft) {
        // The seven calldata parameters are deliberately unnamed: decoding the
        // untouched argument area directly into the struct fields keeps the
        // external entry stack shallow enough for the pinned non-via-IR
        // profile. `msg.data[4:]` is the raw seven-parameter ABI tuple, so no
        // outer tuple offset is expected.
        CreateCollectionParams memory params;
        (
            params.name,
            params.symbol,
            params.policy,
            params.maxSupply,
            params.baseURI,
            params.metadataURI,
            params.metadataResolver
        ) = abi.decode(msg.data[4:], (string, string, address, uint256, string, string, address));

        nft = _create(params);
    }

    /// @dev Shared creation path. All validation is preserved here.
    function _create(CreateCollectionParams memory params) private returns (address nft) {
        address selectedPolicy = _resolvePolicy(params.policy);
        if (params.maxSupply == 0) revert ZeroSupply();
        if (params.metadataResolver != address(0) && params.metadataResolver.code.length == 0) {
            revert ResolverHasNoCode(params.metadataResolver);
        }

        nft = _deploy(params, selectedPolicy);
        INFTRegistry(assetRegistry).registerAsset(nft, selectedPolicy, msg.sender);
        emit CollectionCreated(nft, msg.sender, selectedPolicy, params.maxSupply, params.metadataResolver);
    }

    /// @dev Deploy the collection; `msg.sender` (the factory) is the
    /// constructor's factory and the creator is the original external caller.
    function _deploy(CreateCollectionParams memory params, address selectedPolicy) private returns (address nft) {
        nft = address(
            new AgenticNFT(
                params.name,
                params.symbol,
                address(this),
                selectedPolicy,
                msg.sender,
                params.maxSupply,
                params.baseURI,
                params.metadataURI,
                params.metadataResolver
            )
        );
    }

    /// @dev Resolve `address(0)` to the current policy and require an allowed policy.
    function _resolvePolicy(address policy) private view returns (address selectedPolicy) {
        selectedPolicy = policy == address(0) ? IPolicyRegistry(policyRegistry).currentPolicy() : policy;
        if (selectedPolicy == address(0) || !IPolicyRegistry(policyRegistry).isPolicyAllowed(selectedPolicy)) {
            revert PolicyNotAllowed(selectedPolicy);
        }
    }
}
