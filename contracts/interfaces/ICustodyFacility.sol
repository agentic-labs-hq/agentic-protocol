// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFacility, IMigratableFacility} from "./IFacility.sol";

/// @notice Custody facility interface.
interface ICustodyFacility is IFacility, IMigratableFacility {
    function release(address token, address to, uint256 amount) external; // gated-only
    function releaseNative(address payable to, uint256 amount) external; // public-only, owner
}

/// @notice VAULT template interface (CUSTODY subtype).
interface IVaultFacility is ICustodyFacility {}

/// @notice LAUNCH template interface (CUSTODY subtype).
interface ILaunchFacility is ICustodyFacility {
    function operator() external view returns (address);
    function beneficiary() external view returns (address);
    function setOperator(address operator) external;
    function setBeneficiary(address beneficiary) external;
    function close() external;

    event OperatorSet(address indexed operator);
    event BeneficiarySet(address indexed beneficiary);
    event Closed();
}

/// @notice LOCKER template interface (CUSTODY subtype).
interface ILockerFacility is ICustodyFacility {
    function beneficiary() external view returns (address);
    function unlockTime() external view returns (uint64);
    function setBeneficiary(address beneficiary) external;
    function extend(uint64 newUnlockTime) external;
    function unlock(address token, address to, uint256 amount) external;

    event BeneficiarySet(address indexed beneficiary);
    event UnlockTimeExtended(uint64 newUnlockTime);
}
