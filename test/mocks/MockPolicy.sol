// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal contract used as a registered policy address with code.
contract MockPolicy {
    uint256 public immutable id;

    constructor(uint256 id_) {
        id = id_;
    }
}
