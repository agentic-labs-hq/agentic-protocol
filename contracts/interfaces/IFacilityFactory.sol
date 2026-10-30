// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Standard facility factory interface.
interface IFacilityFactory {
    function policy() external view returns (address);
    function isSupportedType(bytes32 kind) external view returns (bool);
    function codehashOf(bytes32 kind) external view returns (bytes32);
    function createFacility(bytes32 kind, bytes calldata initData) external returns (address facility);

    event FacilityCreated(address indexed facility, bytes32 indexed kind, address indexed creator);
}
