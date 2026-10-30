// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FacilityCategory} from "../../contracts/common/Types.sol";
import {ITransferPolicy} from "../../contracts/interfaces/ITransferPolicy.sol";

/// @notice Shared configurable transfer-policy mock for token and treasury tests.
/// @dev `isMember` is configurable for the treasury migration guard; `canTransfer`
/// defaults to allow and can pin the exact asset/operator/context for token tests.
contract MockTransferPolicy is ITransferPolicy {
    mapping(address => bool) private _members;
    mapping(address => bool) private _revoked;

    /// @notice When true, `isMember` returns true for every address.
    bool public permissive;

    bool public allowed = true;
    bytes32 public denyReason;
    bool public matchArgs;
    address public expectedAsset;
    address public expectedOperator;
    bytes32 public expectedContextHash;

    function setMember(address wallet, bool member) external {
        _members[wallet] = member;
    }

    function setPermissive(bool permissive_) external {
        permissive = permissive_;
    }

    function setRevoked(address account, bool revoked_) external {
        _revoked[account] = revoked_;
    }

    function setAllowed(bool allowed_, bytes32 reason_) external {
        allowed = allowed_;
        denyReason = reason_;
    }

    function setExpectedArgs(address asset_, address operator_, bytes32 contextHash_) external {
        matchArgs = true;
        expectedAsset = asset_;
        expectedOperator = operator_;
        expectedContextHash = contextHash_;
    }

    function canTransfer(address asset, address, address, address operator, bytes calldata context)
        external
        view
        override
        returns (bool allowed_, bytes32 reason)
    {
        if (!allowed) return (false, denyReason);
        if (matchArgs) {
            if (asset != expectedAsset || operator != expectedOperator || keccak256(context) != expectedContextHash) {
                return (false, keccak256("BAD_ARGS"));
            }
        }
        return (true, bytes32(0));
    }

    function isMember(address wallet) external view override returns (bool) {
        return permissive || _members[wallet];
    }

    function isFacility(address) external pure override returns (bool) {
        return false;
    }

    function isEligible(address) external pure override returns (bool) {
        return false;
    }

    function categoryOf(address) external pure override returns (FacilityCategory) {
        return FacilityCategory.NONE;
    }

    function isRevokedFacility(address account) external view override returns (bool) {
        return _revoked[account];
    }

    function replacementOf(address) external pure override returns (address) {
        return address(0);
    }

    function identityRegistry() external pure override returns (address) {
        return address(0);
    }

    function facilityRegistry() external pure override returns (address) {
        return address(0);
    }
}
