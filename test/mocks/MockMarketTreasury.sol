// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Empty treasury double that accepts native BNB fee payments.
contract MockMarketTreasury {
    receive() external payable {}
}
