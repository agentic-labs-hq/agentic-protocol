// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFacility} from "../../contracts/interfaces/IFacility.sol";

/// @notice Non-template contract with the same external surface as `MockFacility`.
/// @dev Simulates a proxy/arbitrary implementation: `factory()` and
/// `facilityType()` can be made to match, but the runtime codehash differs from
/// the canonical template codehash returned by the factory.
contract MockProxyFacility is IFacility {
    address public immutable override factory;
    bytes32 public immutable override facilityType;

    address public override owner;
    address public override pendingOwner;
    uint256 public proxyMarker;

    constructor(address factory_, bytes32 facilityType_, address owner_) {
        factory = factory_;
        facilityType = facilityType_;
        owner = owner_;
    }

    function setProxyMarker(uint256 marker) external {
        proxyMarker = marker;
    }

    function transferOwnership(address newOwner) external override {
        require(msg.sender == owner, "not owner");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external override {
        require(msg.sender == pendingOwner, "not pending owner");
        address previous = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, msg.sender);
    }
}
