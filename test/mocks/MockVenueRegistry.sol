// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FacilityCategory} from "../../contracts/common/Types.sol";

/// @notice Deliberately permissive venue-registry mock used to prove that the
/// policy itself re-checks the revoked-facility replacement (category, subtype,
/// active), not only the real registry's `setReplacement` validation.
contract MockVenueRegistry {
    mapping(address => bool) public isFacility;
    mapping(address => bool) public isRevokedFacility;
    mapping(address => address) public replacementOf;
    mapping(address => FacilityCategory) public facilityCategory;
    mapping(address => bytes32) public facilityType;

    function setFacilityForTest(address account, FacilityCategory category, bytes32 kind, bool active) external {
        isFacility[account] = active;
        facilityCategory[account] = category;
        facilityType[account] = kind;
    }

    function setRevokedForTest(address account, bool revoked) external {
        isRevokedFacility[account] = revoked;
    }

    function setReplacementForTest(address account, address replacement) external {
        replacementOf[account] = replacement;
    }

    function isFacilityOfCategory(address account, FacilityCategory category) external view returns (bool) {
        return isFacility[account] && facilityCategory[account] == category;
    }
}
