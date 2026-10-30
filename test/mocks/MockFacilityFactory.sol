// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFacilityFactory} from "../../contracts/interfaces/IFacilityFactory.sol";
import {MockFacility} from "./MockFacility.sol";

/// @notice Standard-style facility factory used for codehash/append-only tests.
/// @dev Records the runtime codehash of the last facility created for each kind,
/// exactly like a real template factory would return its canonical template hash.
contract MockFacilityFactory is IFacilityFactory {
    address public immutable override policy;

    mapping(bytes32 => bool) private _supported;
    mapping(bytes32 => bytes32) private _codehash;

    constructor(address policy_) {
        policy = policy_;
    }

    function isSupportedType(bytes32 kind) external view override returns (bool) {
        return _supported[kind];
    }

    function codehashOf(bytes32 kind) external view override returns (bytes32) {
        return _codehash[kind];
    }

    function createFacility(bytes32 kind, bytes calldata initData) external override returns (address facility) {
        address owner_ = abi.decode(initData, (address));
        facility = address(new MockFacility(address(this), kind, owner_));
        _supported[kind] = true;
        _codehash[kind] = facility.codehash;
        emit FacilityCreated(facility, kind, msg.sender);
    }

    /// @notice Test hook to simulate a factory returning a wrong/zero template hash.
    function setCodehashForTest(bytes32 kind, bytes32 codehash_) external {
        _codehash[kind] = codehash_;
    }
}
