// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

/// @notice Facility categories, ABI-compatible with the protocol `FacilityCategory`
/// enum. The enum is encoded as `uint8` on the wire, so the
/// 0.7.6 NPM can call a 0.8.20 policy without sharing a compiler version.
enum FacilityCategory {NONE, POOL, LP_MANAGER, FEE_RECIPIENT, CUSTODY, PURPOSE}

/// @notice Read-only transfer-policy view used by the gated NPM
///.
/// @dev LP recipients are agents only: a member whose category is `NONE`.
/// Facilities have a non-`NONE` category and are never valid LP recipients.
interface IGatedTransferPolicy {
    function isMember(address wallet) external view returns (bool);
    function categoryOf(address account) external view returns (FacilityCategory);
}
