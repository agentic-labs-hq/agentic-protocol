// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgenticFacilityBase} from "../../contracts/facility/AgenticFacilityBase.sol";

/// @notice Minimal concrete `AgenticFacilityBase` used to exercise the migration guard
/// against a deliberately permissive/mock venue registry. Production templates
/// are always deployed through the factory; this harness has no asset functions.
contract AgenticFacilityBaseHarness is AgenticFacilityBase {
    constructor(address factory_, bytes32 facilityType_, address venueRegistry_, address assetRegistry_, address owner_)
        AgenticFacilityBase(factory_, facilityType_, venueRegistry_, assetRegistry_, owner_)
    {}
}
