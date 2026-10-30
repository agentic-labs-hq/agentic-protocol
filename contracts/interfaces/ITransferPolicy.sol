// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FacilityCategory} from "../common/Types.sol";

/// @notice Transfer gate interface.
interface ITransferPolicy {
    function canTransfer(address asset, address from, address to, address operator, bytes calldata context)
        external
        view
        returns (bool allowed, bytes32 reason);

    function isMember(address wallet) external view returns (bool);
    function isFacility(address account) external view returns (bool);
    function isEligible(address account) external view returns (bool);
    function categoryOf(address account) external view returns (FacilityCategory);
    function isRevokedFacility(address account) external view returns (bool);
    function replacementOf(address account) external view returns (address);

    function identityRegistry() external view returns (address);
    function facilityRegistry() external view returns (address);
}
