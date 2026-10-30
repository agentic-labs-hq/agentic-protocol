// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

/// @notice Test-only transfer policy with a mutable member/category matrix.
/// @dev Categories use the protocol `FacilityCategory` encoding (0 = NONE, agent;
/// 1 = POOL, 2 = LP_MANAGER, 3 = FEE_RECIPIENT, 4 = CUSTODY, 5 = PURPOSE).
contract MockTransferPolicy {
    mapping(address => bool) private _isMember;
    mapping(address => uint8) private _categoryOf;

    function setMember(address wallet, bool member) external {
        _isMember[wallet] = member;
    }

    function setCategory(address account, uint8 category) external {
        _categoryOf[account] = category;
    }

    function isMember(address wallet) external view returns (bool) {
        return _isMember[wallet];
    }

    function categoryOf(address account) external view returns (uint8) {
        return _categoryOf[account];
    }
}
