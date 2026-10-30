// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FacilityCategory} from "../common/Types.sol";
import {IGovernance} from "./IGovernance.sol";

/// @notice Facility (venue) registry interface.
/// @dev Per the approved E1 erratum, `FacilityRegistered.factory` is not indexed
/// because solc 0.8.20 allows at most three indexed event arguments. The ABI
/// event signature/selector is unchanged; only the topic layout differs.
interface IVenueRegistry is IGovernance {
    function isFacility(address account) external view returns (bool);
    function facilityType(address account) external view returns (bytes32);
    function facilityCategory(address account) external view returns (FacilityCategory);
    function isFacilityOfCategory(address account, FacilityCategory category) external view returns (bool);
    function isFacilityOfType(address account, bytes32 kind) external view returns (bool);
    function isRevokedFacility(address account) external view returns (bool);
    function replacementOf(address account) external view returns (address);
    function factoryOf(address account) external view returns (address);
    function categoryOfType(bytes32 kind) external view returns (FacilityCategory);
    function isRegistrarFor(address account, FacilityCategory category) external view returns (bool);

    function addTypeCategory(bytes32 kind, FacilityCategory category) external;
    function setRegistrar(address account, FacilityCategory category, bool enabled) external;
    function registerFacility(address account, bytes32 kind) external;
    function revokeFacility(address account) external;
    function setReplacement(address account, address replacement) external;

    event TypeCategoryAdded(bytes32 indexed kind, FacilityCategory category);
    event RegistrarSet(address indexed account, FacilityCategory indexed category, bool enabled);
    event FacilityRegistered(
        address indexed account, bytes32 indexed kind, FacilityCategory indexed category, address factory
    );
    event FacilityRevoked(address indexed account, bytes32 indexed kind);
    event ReplacementSet(address indexed account, address indexed replacement);
}
