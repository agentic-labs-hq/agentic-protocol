// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Gated Uniswap V3 non-fungible position manager interface.
/// @dev The standard NPM surface (mint/increase/decrease/collect/burn/positions/tokenURI)
/// is supplied by the DEX implementation and per-token policy checks; the initial protocol release defines only
/// the protocol-specific functions below.
interface IGatedPositionManager {
    function policyOfToken(address token) external view returns (address);

    function isAllowedRecipient(address token, address to) external view returns (bool);
    function isAllowedTransfer(uint256 tokenId, address from, address to) external view returns (bool);
}
