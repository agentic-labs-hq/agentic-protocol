// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FacilityCategory} from "../../contracts/common/Types.sol";

/// @notice Minimal venue-registry double for Agentmarket.
/// @dev Agentmarket only asks whether an account is an active `FEE_RECIPIENT`.
/// Every other category is always false.
contract MockMarketVenue {
    mapping(address => bool) private _feeRecipients;

    /// @notice Test hook: mark an account as an active (or inactive) fee recipient.
    function setFeeRecipient(address account, bool active) external {
        _feeRecipients[account] = active;
    }

    function isFacilityOfCategory(address account, FacilityCategory category) external view returns (bool) {
        return category == FacilityCategory.FEE_RECIPIENT && _feeRecipients[account];
    }
}
