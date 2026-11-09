// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssetType} from "../common/Types.sol";
import {Governance2Step} from "../common/Governance2Step.sol";
import {IAgentNFT} from "../interfaces/IAgentNFT.sol";
import {INFTRegistry} from "../interfaces/INFTRegistry.sol";
import {IPolicyRegistry} from "../interfaces/IPolicyRegistry.sol";

/// @notice Gated NFT collection registry (INTERFACES v2.3 §NFT).
/// @dev Provenance only. Collections can only be registered by a
/// governance-enabled registrar whose address is stamped as the collection's
/// factory, so no arbitrary contract can be recorded as a gated NFT. The
/// registry is never in the transfer path: the collection's policy alone
/// decides eligibility. Unlike the FT asset registry there is no pool surface.
contract AgenticNFTRegistry is INFTRegistry, Governance2Step {
    /// @inheritdoc INFTRegistry
    address public immutable override policyRegistry;

    /// @inheritdoc INFTRegistry
    mapping(address => bool) public override isRegistered;

    /// @inheritdoc INFTRegistry
    mapping(address => address) public override policyOf;

    /// @inheritdoc INFTRegistry
    mapping(address => address) public override creatorOf;

    /// @inheritdoc INFTRegistry
    mapping(address => bool) public override isRegistrar;

    /// @notice Thrown when a registry address is zero.
    error ZeroRegistry();
    /// @notice Thrown when a registry address has no code.
    error RegistryHasNoCode(address registry);
    /// @notice Thrown when the registrar is zero.
    error ZeroRegistrar();
    /// @notice Thrown when a registrar has no code.
    error RegistrarHasNoCode(address account);
    /// @notice Thrown when the caller is not an asset registrar.
    error NotRegistrar(address caller);
    /// @notice Thrown when the collection is zero.
    error ZeroAsset();
    /// @notice Thrown when the collection has no code.
    error AssetHasNoCode(address asset);
    /// @notice Thrown when the collection is already registered.
    error AssetAlreadyRegistered(address asset);
    /// @notice Thrown when the collection's factory stamp differs from the caller.
    error FactoryMismatch(address asset, address expected, address actual);
    /// @notice Thrown when the supplied policy differs from the collection's policy.
    error PolicyMismatch(address asset, address expected, address actual);
    /// @notice Thrown when the policy is not registered/allowed.
    error PolicyNotAllowed(address policy);
    /// @notice Thrown when the supplied creator differs from the collection's creator.
    error CreatorMismatch(address asset, address expected, address actual);
    /// @notice Thrown when the asset type is not NFT.
    error AssetTypeNotSupported(address asset, AssetType actual);

    /// @param governance_ Initial two-step governance.
    /// @param policyRegistry_ Versioned policy registry.
    constructor(address governance_, address policyRegistry_) Governance2Step(governance_) {
        if (policyRegistry_ == address(0)) revert ZeroRegistry();
        if (policyRegistry_.code.length == 0) revert RegistryHasNoCode(policyRegistry_);
        policyRegistry = policyRegistry_;
    }

    /// @inheritdoc INFTRegistry
    /// @dev Only a governance-enabled `AgenticNFTRegistry` registrar (the
    /// `AgenticNFTFactory`) may register, and the collection's factory stamp
    /// must be that same caller. This binds every record to a real factory
    /// deployment.
    function registerAsset(address nft, address policy, address creator) external override {
        if (!isRegistrar[msg.sender]) revert NotRegistrar(msg.sender);
        if (nft == address(0)) revert ZeroAsset();
        if (nft.code.length == 0) revert AssetHasNoCode(nft);
        if (isRegistered[nft]) revert AssetAlreadyRegistered(nft);

        address actualFactory = IAgentNFT(nft).factory();
        if (actualFactory != msg.sender) revert FactoryMismatch(nft, msg.sender, actualFactory);

        address actualPolicy = IAgentNFT(nft).policy();
        if (actualPolicy != policy) revert PolicyMismatch(nft, policy, actualPolicy);
        if (!IPolicyRegistry(policyRegistry).isPolicyAllowed(policy)) revert PolicyNotAllowed(policy);

        address actualCreator = IAgentNFT(nft).creator();
        if (actualCreator != creator) revert CreatorMismatch(nft, creator, actualCreator);

        AssetType actualType = IAgentNFT(nft).assetType();
        if (actualType != AssetType.NFT) revert AssetTypeNotSupported(nft, actualType);

        isRegistered[nft] = true;
        policyOf[nft] = policy;
        creatorOf[nft] = creator;
        emit AssetRegistered(nft, policy, creator);
    }

    /// @inheritdoc INFTRegistry
    /// @dev Governance sets the NFT registrars (the `AgenticNFTFactory`). A
    /// registrar must be a contract; disabling is allowed but still requires code.
    function setRegistrar(address account, bool enabled) external override onlyGovernance {
        if (account == address(0)) revert ZeroRegistrar();
        if (account.code.length == 0) revert RegistrarHasNoCode(account);
        isRegistrar[account] = enabled;
        emit RegistrarSet(account, enabled);
    }
}
