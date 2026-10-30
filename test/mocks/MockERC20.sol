// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal public ERC-20 used as a quote asset in registry tests.
/// @dev Only the probe surface (`totalSupply`/`balanceOf`) is needed by
/// `AgenticQuoteAssetRegistry`; transfers are irrelevant for an allowlist entry.
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}

/// @notice Contract that answers `totalSupply()` but not `balanceOf()`.
contract MockERC20NoBalanceOf {
    function totalSupply() external pure returns (uint256) {
        return 0;
    }
}

/// @notice Contract whose `totalSupply()` call reverts.
contract MockERC20RevertingTotalSupply {
    function totalSupply() external pure returns (uint256) {
        revert("NO_SUPPLY");
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }
}
