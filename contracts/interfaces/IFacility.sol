// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Facility ownership surface.
interface IFacility {
    function factory() external view returns (address);
    function facilityType() external view returns (bytes32);
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);

    function transferOwnership(address newOwner) external;
    function acceptOwnership() external;

    event OwnershipTransferStarted(address indexed current, address indexed pending);
    event OwnershipTransferred(address indexed previous, address indexed newOwner);
}

/// @notice Revoked-facility migration surface.
interface IMigratableFacility {
    function migrate(address replacement) external;
}
