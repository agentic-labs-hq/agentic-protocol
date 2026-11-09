// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @notice Minimal permissionless-mint ERC721 used by the Agentmarket unit tests.
contract MockMarketNFT is ERC721 {
    constructor() ERC721("Mock Market NFT", "MMNFT") {}

    /// @notice Test hook: mint `tokenId` to `to` without any access control.
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}
