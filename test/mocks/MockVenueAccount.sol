// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Empty contract used as a POOL/LP_MANAGER/FEE_RECIPIENT venue account.
/// @dev Those categories trust the per-category registrar in the venue registry, so the
/// account does not need to implement `IFacility`.
contract MockVenueAccount {}
