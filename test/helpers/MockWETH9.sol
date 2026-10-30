// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal WETH9 for the 0.7.6 periphery constructors.
/// @dev No mainnet address: the cross-version tests deploy this mock and pass
/// its address to the AgentswapRouter/AgentswapQuoter/NPM. Only ERC-20 swaps are exercised, so
/// the native wrap/unwrap paths are present for ABI completeness, not used.
contract MockWETH9 {
    string public constant name = "Mock Wrapped Ether";
    string public constant symbol = "mWETH";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) external {
        require(balanceOf[msg.sender] >= wad, "MockWETH9: balance");
        balanceOf[msg.sender] -= wad;
        totalSupply -= wad;
        (bool ok,) = msg.sender.call{value: wad}("");
        require(ok, "MockWETH9: send");
        emit Withdrawal(msg.sender, wad);
    }

    function approve(address guy, uint256 wad) external returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint256 wad) external returns (bool) {
        return _transfer(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad) external returns (bool) {
        uint256 allowed = allowance[src][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= wad, "MockWETH9: allowance");
            allowance[src][msg.sender] = allowed - wad;
        }
        return _transfer(src, dst, wad);
    }

    function _transfer(address src, address dst, uint256 wad) private returns (bool) {
        require(balanceOf[src] >= wad, "MockWETH9: balance");
        balanceOf[src] -= wad;
        balanceOf[dst] += wad;
        emit Transfer(src, dst, wad);
        return true;
    }
}
