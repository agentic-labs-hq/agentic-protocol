// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

/// @dev Minimal membership view used by the mock token. Matches the subset of
/// the protocol `ITransferPolicy` (0.8.20) that decides agent eligibility.
interface IPolicyMembership {
    function isMember(address wallet) external view returns (bool);
    function categoryOf(address account) external view returns (uint8);
}

/// @notice Test-only policy-aware ERC20 (0.7.6 stand-in for the 0.8.20 gated
/// `AgenticToken`) used to prove the router/quoter add no transfer gate and no
/// bypass of their own.
/// @dev The token, not the router, enforces the policy: agents (member with
/// category NONE) may send to agents or to a registered pool facility; a pool
/// may send only to agents. That mirrors the protocol AgenticPolicy rules relevant to
/// swaps. The real cross-version token/policy test remains the gated fork.
contract MockPolicyToken {
    uint8 private constant CATEGORY_NONE = 0;
    uint8 private constant CATEGORY_POOL = 1;

    IPolicyMembership public immutable policy;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(address policy_, uint256 initialSupply) {
        require(policy_ != address(0), "policy: zero");
        policy = IPolicyMembership(policy_);
        _mint(msg.sender, initialSupply);
    }

    /// @dev Test-only funding path. Real gated tokens mint through the factory;
    /// minting here is from address(0) and does not exercise transfer policy.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        require(_isAllowed(msg.sender, recipient), "policy: denied");
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        require(_isAllowed(sender, recipient), "policy: denied");
        uint256 allowed = allowance[sender][msg.sender];
        require(allowed >= amount, "policy: allowance");
        allowance[sender][msg.sender] = allowed - amount;
        _transfer(sender, recipient, amount);
        return true;
    }

    function _isAgent(address account) private view returns (bool) {
        return policy.isMember(account) && policy.categoryOf(account) == CATEGORY_NONE;
    }

    function _isAllowed(address from, address to) private view returns (bool) {
        if (from == address(0) || to == address(0)) return true;
        if (policy.categoryOf(from) == CATEGORY_POOL) return _isAgent(to);
        if (!_isAgent(from)) return false;
        return policy.categoryOf(to) == CATEGORY_POOL || _isAgent(to);
    }

    function _mint(address to, uint256 amount) private {
        require(to != address(0), "policy: zero");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(balanceOf[from] >= amount, "policy: balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
