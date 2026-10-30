// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Gated FT mock that returns the policy configured at construction.
/// @dev `AgenticTreasury` reads `policy()` and then asks that policy for
/// `isMember`; the token itself is a plain ERC-20 so balances are observable.
contract MockAgenticToken is ERC20 {
    /// @notice Transfer policy returned by `policy()`.
    address public immutable policy;

    constructor(address policy_) ERC20("Mock Agent Token", "MAT") {
        policy = policy_;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}
