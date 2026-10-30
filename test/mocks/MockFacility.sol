// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFacility} from "../../contracts/interfaces/IFacility.sol";

/// @notice Standard-style facility template used for CUSTODY/PURPOSE registry tests.
/// @dev Only `factory`/`facilityType` are immutable, so two facilities of the same
/// factory and kind share one runtime codehash (the R2 condition). The owner is
/// storage and transfer is two-step.
contract MockFacility is IFacility {
    address public immutable override factory;
    bytes32 public immutable override facilityType;

    address public override owner;
    address public override pendingOwner;

    error NotOwner();
    error NotPendingOwner();

    constructor(address factory_, bytes32 facilityType_, address owner_) {
        factory = factory_;
        facilityType = facilityType_;
        owner = owner_;
    }

    function transferOwnership(address newOwner) external override {
        if (msg.sender != owner) revert NotOwner();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external override {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        address previous = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, msg.sender);
    }
}
