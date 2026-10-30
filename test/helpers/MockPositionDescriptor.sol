// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal position descriptor for the 0.7.6 NPM constructor.
/// @dev The NPM only calls `tokenURI(this, tokenId)` on the descriptor. Keeping
/// it a deployed root mock (rather than a mainnet address or a codeless
/// placeholder) exercises the 0.7.6 -> 0.8.20 read in the NPM `tokenURI` path.
contract MockPositionDescriptor {
    string internal constant POSITION_URI = "mock://dex-position";

    function tokenURI(address, uint256) external pure returns (string memory) {
        return POSITION_URI;
    }
}
