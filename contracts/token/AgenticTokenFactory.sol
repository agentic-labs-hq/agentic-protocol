// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssetType, FacilityCategory} from "../common/Types.sol";
import {IAgentTokenFactory} from "../interfaces/IAgentTokenFactory.sol";
import {IAssetRegistry} from "../interfaces/IAssetRegistry.sol";
import {IPolicyRegistry} from "../interfaces/IPolicyRegistry.sol";
import {ITransferPolicy} from "../interfaces/ITransferPolicy.sol";
import {IVenueRegistry} from "../interfaces/IVenueRegistry.sol";
import {AgenticToken} from "./AgenticToken.sol";

/// @notice Permissionless gated-token factory.
/// @dev The caller needs no Agent ID: an agent or a project can create a token
/// and becomes its immutable creator. The factory only deploys `AgenticToken`
/// contracts, mints the entire initial supply to the caller-supplied
/// recipients (never to itself), registers the asset in `AgenticAssetRegistry`, and
/// then has no further role: there is no admin mint, pause, upgrade or proxy.
contract AgenticTokenFactory is IAgentTokenFactory {
    /// @inheritdoc IAgentTokenFactory
    address public immutable override policyRegistry;

    /// @inheritdoc IAgentTokenFactory
    address public immutable override assetRegistry;

    /// @inheritdoc IAgentTokenFactory
    address public immutable override facilityRegistry;

    /// @inheritdoc IAgentTokenFactory
    uint256 public immutable override maxRecipients;

    /// @notice Thrown when a registry/zero address argument is invalid.
    error ZeroRegistry();
    /// @notice Thrown when a configured address is not a contract.
    error RegistryHasNoCode(address registry);
    /// @notice Thrown when `maxRecipients` is zero.
    error InvalidMaxRecipients();
    /// @notice Thrown when a recipient and amount array have different lengths.
    error LengthMismatch();
    /// @notice Thrown when the recipient count is outside `[1, maxRecipients]`.
    error InvalidRecipientCount(uint256 count, uint256 maxRecipients);
    /// @notice Thrown when the policy is not registered/allowed.
    error PolicyNotAllowed(address policy);
    /// @notice Thrown when the total initial supply is zero.
    error ZeroInitialSupply();
    /// @notice Thrown for the zero recipient address.
    error ZeroRecipient();
    /// @notice Thrown for a duplicate initial recipient.
    error DuplicateRecipient(address recipient);
    /// @notice Thrown for a POOL/LP_MANAGER/FEE_RECIPIENT or unknown category.
    error RecipientCategoryNotAllowed(address recipient, FacilityCategory category);
    /// @notice Thrown for a registered but revoked CUSTODY/PURPOSE facility.
    error RecipientNotActiveFacility(address recipient);
    /// @notice Thrown for a non-facility address without an Agent ID.
    error RecipientNotEligible(address recipient);

    /// @dev Creation arguments decoded from `msg.data[4:]`. The field order and
    /// types exactly mirror the frozen six-parameter ABI tuple, so the external
    /// selector is unchanged (`createToken(string,string,address,address[],uint256[],string)`).
    struct CreateTokenParams {
        string name;
        string symbol;
        address policy;
        address[] initialRecipients;
        uint256[] initialAmounts;
        string metadataURI;
    }

    /// @param policyRegistry_ Versioned policy registry.
    /// @param assetRegistry_ Asset registry that records created tokens.
    /// @param facilityRegistry_ Venue registry used for recipient category checks.
    /// @param maxRecipients_ Maximum number of initial recipients per token.
    constructor(address policyRegistry_, address assetRegistry_, address facilityRegistry_, uint256 maxRecipients_) {
        if (policyRegistry_ == address(0) || assetRegistry_ == address(0) || facilityRegistry_ == address(0)) {
            revert ZeroRegistry();
        }
        if (policyRegistry_.code.length == 0 || assetRegistry_.code.length == 0 || facilityRegistry_.code.length == 0) {
            revert RegistryHasNoCode(_codeless(policyRegistry_, assetRegistry_, facilityRegistry_));
        }
        if (maxRecipients_ == 0) revert InvalidMaxRecipients();

        policyRegistry = policyRegistry_;
        assetRegistry = assetRegistry_;
        facilityRegistry = facilityRegistry_;
        maxRecipients = maxRecipients_;
    }

    /// @inheritdoc IAgentTokenFactory
    /// @dev `policy == address(0)` resolves to `currentPolicy()`. Explicit
    /// policies must be registered and not deprecated. Each recipient must be an
    /// agent or an active CUSTODY/PURPOSE facility; POOL, LP_MANAGER and
    /// FEE_RECIPIENT recipients are always rejected. The whole initial supply
    /// is minted in the token constructor to the recipients, then the asset is
    /// registered. Any failure reverts the whole creation.
    function createToken(
        string calldata,
        string calldata,
        address,
        address[] calldata,
        uint256[] calldata,
        string calldata
    ) external override returns (address token) {
        // The six calldata parameters are deliberately unnamed: decoding the
        // untouched argument area into these locals keeps the external entry
        // stack shallow (the stack-too-deep fix for the pinned non-via-IR
        // profile). `msg.data[4:]` is the raw six-parameter ABI tuple, so the
        // element types must be decoded individually before packing the struct;
        // an `(CreateTokenParams)` decode would expect the extra outer tuple
        // offset that a function selector strips.
        (
            string memory name,
            string memory symbol,
            address policy,
            address[] memory initialRecipients,
            uint256[] memory initialAmounts,
            string memory metadataURI
        ) = abi.decode(msg.data[4:], (string, string, address, address[], uint256[], string));
        token = _create(CreateTokenParams(name, symbol, policy, initialRecipients, initialAmounts, metadataURI));
    }

    /// @dev Shared creation path. All validation is preserved here.
    function _create(CreateTokenParams memory params) private returns (address token) {
        uint256 count = params.initialRecipients.length;
        if (count != params.initialAmounts.length) revert LengthMismatch();
        if (count == 0 || count > maxRecipients) revert InvalidRecipientCount(count, maxRecipients);

        address selectedPolicy = _resolvePolicy(params.policy);
        _validateRecipients(selectedPolicy, params.initialRecipients, params.initialAmounts);

        token = _deploy(params, selectedPolicy);
        IAssetRegistry(assetRegistry).registerAsset(token, selectedPolicy, msg.sender);
        emit TokenCreated(token, msg.sender, selectedPolicy);
    }

    /// @dev Deploy the token; `msg.sender` (the factory) is the constructor's
    /// factory and the creator is the original external caller.
    function _deploy(CreateTokenParams memory params, address selectedPolicy) private returns (address token) {
        token = address(
            new AgenticToken(
                params.name,
                params.symbol,
                address(this),
                selectedPolicy,
                msg.sender,
                params.initialRecipients,
                params.initialAmounts,
                params.metadataURI
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

    /// @dev Validate every recipient and the non-zero total supply.
    function _validateRecipients(
        address selectedPolicy,
        address[] memory initialRecipients,
        uint256[] memory initialAmounts
    ) private view {
        IVenueRegistry venue = IVenueRegistry(facilityRegistry);
        ITransferPolicy transferPolicy = ITransferPolicy(selectedPolicy);
        uint256 total = 0;
        uint256 count = initialRecipients.length;
        for (uint256 i; i < count; ++i) {
            address recipient = initialRecipients[i];
            if (recipient == address(0)) revert ZeroRecipient();
            for (uint256 j; j < i; ++j) {
                if (initialRecipients[j] == recipient) revert DuplicateRecipient(recipient);
            }
            _checkRecipient(transferPolicy, venue, recipient);
            total += initialAmounts[i];
        }
        if (total == 0) revert ZeroInitialSupply();
    }

    /// @dev Enforce the initial-recipient category matrix without trusting the
    /// factory caller. A facility's category always takes precedence over any
    /// Agent ID it may also hold, so a POOL/LP_MANAGER/FEE_RECIPIENT can never
    /// receive the initial supply. CUSTODY/PURPOSE must be active (revoked
    /// facilities are frozen and cannot receive new gated supply).
    function _checkRecipient(ITransferPolicy transferPolicy, IVenueRegistry venue, address recipient) private view {
        FacilityCategory category = transferPolicy.categoryOf(recipient);
        if (category == FacilityCategory.CUSTODY || category == FacilityCategory.PURPOSE) {
            if (!venue.isFacilityOfCategory(recipient, category)) revert RecipientNotActiveFacility(recipient);
            return;
        }
        if (category != FacilityCategory.NONE) revert RecipientCategoryNotAllowed(recipient, category);
        if (!transferPolicy.isMember(recipient)) revert RecipientNotEligible(recipient);
    }

    /// @dev Returns the first codeless registry for the constructor error.
    function _codeless(address a, address b, address c) private view returns (address) {
        if (a.code.length == 0) return a;
        if (b.code.length == 0) return b;
        return c;
    }
}
