// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FacilityCategory, TransferKind} from "../common/Types.sol";
import {ITransferPolicy} from "../interfaces/ITransferPolicy.sol";
import {IIdentityAdapter, IIdentityAdapterRegistry} from "../interfaces/IIdentityAdapter.sol";
import {IVenueRegistry} from "../interfaces/IVenueRegistry.sol";

/// @notice Agent ID gated transfer policy, category matrix v1.
/// @dev The policy is immutable: it reads the Agent ID adapter registry and the
/// venue registry live, never caches, and has no admin override, no arbitrary
/// allowlist and no per-project path. A facility is classified by its registry
/// category; an address is an "agent" only through the registered identity
/// adapter. Facility category takes precedence over identity so a facility that
/// somehow holds an Agent ID can never use the agent row/column.
contract AgenticPolicy is ITransferPolicy {
    /// @notice Protocol-wide Agent ID adapter kind label.
    /// @dev Integration constant (not a public interface): the policy registry registers the
    /// Agent ID adapter under `keccak256("AGENT_ID")`; this policy looks up the
    /// same kind. No adapter => every membership check is false (fail-closed).
    bytes32 public constant AGENT_ID_KIND = keccak256("AGENT_ID");

    /// @inheritdoc ITransferPolicy
    address public immutable override identityRegistry;

    /// @inheritdoc ITransferPolicy
    address public immutable override facilityRegistry;

    bytes32 internal constant REASON_INVALID_CONTEXT = keccak256("INVALID_TRANSFER_CONTEXT");
    bytes32 internal constant REASON_ZERO_RECIPIENT = keccak256("ZERO_RECIPIENT");
    bytes32 internal constant REASON_NOT_ELIGIBLE = keccak256("NOT_ELIGIBLE");
    bytes32 internal constant REASON_REVOKED_FACILITY = keccak256("REVOKED_FACILITY");
    bytes32 internal constant REASON_FACILITY_TO_FACILITY = keccak256("FACILITY_TO_FACILITY");
    bytes32 internal constant REASON_CATEGORY_DENIED = keccak256("CATEGORY_DENIED");

    error ZeroRegistry();

    constructor(address identityRegistry_, address facilityRegistry_) {
        if (identityRegistry_ == address(0) || facilityRegistry_ == address(0)) revert ZeroRegistry();
        identityRegistry = identityRegistry_;
        facilityRegistry = facilityRegistry_;
    }

    /// @inheritdoc ITransferPolicy
    function canTransfer(address, address from, address to, address, bytes calldata context)
        external
        view
        override
        returns (bool allowed, bytes32 reason)
    {
        if (!_isTransferContext(context)) return (false, REASON_INVALID_CONTEXT);
        if (to == address(0)) return (false, REASON_ZERO_RECIPIENT);

        IVenueRegistry venue = IVenueRegistry(facilityRegistry);

        // A revoked facility is never a valid recipient, even if it also holds
        // an Agent ID. `isFacility` is active-only, so this check must precede
        // every identity/agent fallback and the mint branch.
        if (venue.isRevokedFacility(to)) return (false, REASON_REVOKED_FACILITY);

        // Mint: the only exception. Eligibility is the live member/facility check;
        // the token factory applies the tighter initial-recipient category check.
        if (from == address(0)) {
            if (isEligible(to)) return (true, bytes32(0));
            return (false, REASON_NOT_ELIGIBLE);
        }

        // A revoked facility is frozen: its only outbound direction is the
        // registry replacement of the same category and subtype, if active.
        if (venue.isRevokedFacility(from)) {
            address replacement = venue.replacementOf(from);
            if (
                replacement != address(0) && to == replacement
                    && venue.isFacilityOfCategory(to, venue.facilityCategory(from))
                    && venue.facilityType(from) == venue.facilityType(to)
            ) {
                return (true, bytes32(0));
            }
            return (false, REASON_REVOKED_FACILITY);
        }

        bool fromIsFacility = venue.isFacility(from);
        bool toIsFacility = venue.isFacility(to);

        if (fromIsFacility) {
            FacilityCategory fromCategory = venue.facilityCategory(from);

            if (toIsFacility) {
                FacilityCategory toCategory = venue.facilityCategory(to);
                // The only protocol facility -> facility exception. POOL may
                // pay protocol fees to FEE_RECIPIENT. There is deliberately no
                // POOL -> LP_MANAGER exception: the NPM never needs to receive
                // gated tokens, and removing it closes the permissionless
                // `sweepToken` route for gated donations.
                if (fromCategory == FacilityCategory.POOL && toCategory == FacilityCategory.FEE_RECIPIENT) {
                    return (true, bytes32(0));
                }
                return (false, REASON_FACILITY_TO_FACILITY);
            }

            // Every facility category may send gated only to an agent.
            if (isMember(to)) return (true, bytes32(0));
            return (false, REASON_NOT_ELIGIBLE);
        }

        // Non-facility `from` must be an agent; non-agent EOAs are denied.
        if (!isMember(from)) return (false, REASON_NOT_ELIGIBLE);

        if (toIsFacility) {
            FacilityCategory toCategory = venue.facilityCategory(to);
            // Agent row: agent, POOL and PURPOSE are allowed; LP/FEE/CUSTODY are not.
            if (toCategory == FacilityCategory.POOL || toCategory == FacilityCategory.PURPOSE) {
                return (true, bytes32(0));
            }
            return (false, REASON_CATEGORY_DENIED);
        }

        if (isMember(to)) return (true, bytes32(0));
        return (false, REASON_NOT_ELIGIBLE);
    }

    /// @inheritdoc ITransferPolicy
    function isMember(address wallet) public view override returns (bool) {
        if (wallet == address(0)) return false;
        address adapter = IIdentityAdapterRegistry(identityRegistry).adapterOf(AGENT_ID_KIND);
        if (adapter == address(0)) return false;
        return IIdentityAdapter(adapter).hasIdentity(wallet);
    }

    /// @inheritdoc ITransferPolicy
    function isFacility(address account) public view override returns (bool) {
        return IVenueRegistry(facilityRegistry).isFacility(account);
    }

    /// @inheritdoc ITransferPolicy
    function isEligible(address account) public view override returns (bool) {
        if (isRevokedFacility(account)) return false;
        return isFacility(account) || isMember(account);
    }

    /// @inheritdoc ITransferPolicy
    function categoryOf(address account) public view override returns (FacilityCategory) {
        return IVenueRegistry(facilityRegistry).facilityCategory(account);
    }

    /// @inheritdoc ITransferPolicy
    function isRevokedFacility(address account) public view override returns (bool) {
        return IVenueRegistry(facilityRegistry).isRevokedFacility(account);
    }

    /// @inheritdoc ITransferPolicy
    function replacementOf(address account) public view override returns (address) {
        return IVenueRegistry(facilityRegistry).replacementOf(account);
    }

    /// @dev `context` must be exactly `abi.encode(TransferKind.TRANSFER)`. Any
    /// other length or value denies instead of reverting.
    function _isTransferContext(bytes calldata context) private pure returns (bool) {
        if (context.length != 32) return false;
        uint256 kind;
        // Read the raw word so an out-of-range enum value also returns `false`
        // instead of triggering the compiler's enum validation revert.
        assembly ("memory-safe") {
            kind := calldataload(context.offset)
        }
        return kind == uint256(TransferKind.TRANSFER);
    }
}
