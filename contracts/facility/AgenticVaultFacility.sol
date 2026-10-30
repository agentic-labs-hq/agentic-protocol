// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {VAULT} from "../common/Types.sol";
import {ICustodyFacility, IVaultFacility} from "../interfaces/ICustodyFacility.sol";
import {AgenticFacilityBase} from "./AgenticFacilityBase.sol";

/// @notice CUSTODY/VAULT: project treasury with multi-token gated release
///. `release` is owner-only and gated->agent; `releaseNative`
/// is owner-only public native. There is no public release and no facility
/// recipient outside the registry-validated migration target.
contract AgenticVaultFacility is AgenticFacilityBase, IVaultFacility {
    using SafeERC20 for IERC20;

    /// @notice Emitted when gated or public tokens are released.
    event TokenReleased(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted when public native is released.
    event NativeReleased(address indexed to, uint256 amount);

    /// @param factory_ The facility factory stamp; the factory's deployment helper enforces the caller.
    /// @param venueRegistry_ Venue registry for migration validation.
    /// @param assetRegistry_ Asset registry used to classify gated vs public ERC20.
    /// @param owner_ Project owner (no Agent ID required).
    constructor(address factory_, address venueRegistry_, address assetRegistry_, address owner_)
        AgenticFacilityBase(factory_, VAULT, venueRegistry_, assetRegistry_, owner_)
    {}

    /// @notice Accept public native.
    receive() external payable {}

    /// @inheritdoc ICustodyFacility
    /// @dev Owner-only. A gated token may only go to an agent or the active
    /// migration target. A public ERC20 (not in the asset registry) may go to
    /// any non-zero recipient; public assets are free.
    function release(address token, address to, uint256 amount) external override nonReentrant onlyOwner {
        if (token == address(0)) revert ZeroToken();
        if (to == address(0)) revert ZeroRecipient();
        if (_isGated(token)) _checkGatedRecipient(token, to);
        emit TokenReleased(token, to, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc ICustodyFacility
    /// @dev Owner-only public native; no agent restriction.
    function releaseNative(address payable to, uint256 amount) external override nonReentrant onlyOwner {
        emit NativeReleased(to, amount);
        _sendNative(to, amount);
    }
}
