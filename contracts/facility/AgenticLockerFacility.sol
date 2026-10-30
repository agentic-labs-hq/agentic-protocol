// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {LOCKER} from "../common/Types.sol";
import {ICustodyFacility, ILockerFacility} from "../interfaces/ICustodyFacility.sol";
import {AgenticFacilityBase} from "./AgenticFacilityBase.sol";

/// @notice CUSTODY/LOCKER: time-locked gated tokens for a fixed agent
/// beneficiary. `unlock` is callable by anyone after
/// `unlockTime`, only to the beneficiary (or the active migration target).
/// `extend`/`setBeneficiary` are owner-only; the beneficiary is agent-only and
/// can only be changed before unlock. `release`/`releaseNative` always revert:
/// LOCKER has no public assets and no generic release path.
contract AgenticLockerFacility is AgenticFacilityBase, ILockerFacility {
    using SafeERC20 for IERC20;

    /// @inheritdoc ILockerFacility
    address public override beneficiary;

    /// @inheritdoc ILockerFacility
    uint64 public override unlockTime;

    error ZeroBeneficiary();
    error UnlockTimeNotReached(uint64 unlockTime);
    error UnlockRecipientNotBeneficiary(address recipient, address beneficiary);
    error UnlockTimeNotExtended(uint64 currentTime, uint64 newTime);
    error UnlockTimeReached(uint64 unlockTime);
    error ReleaseNotSupported();
    error NativeNotSupported();

    /// @notice Emitted when the locked gated balance is unlocked.
    event Unlocked(address indexed token, address indexed to, uint256 amount);

    /// @param factory_ The facility factory stamp; the factory's deployment helper enforces the caller.
    /// @param venueRegistry_ Venue registry for migration validation.
    /// @param assetRegistry_ Asset registry used to classify gated vs public ERC20.
    /// @param owner_ Project owner (no Agent ID required).
    /// @param beneficiary_ Agent beneficiary (may be zero until owner sets it).
    /// @param unlockTime_ Absolute Unix unlock time.
    constructor(
        address factory_,
        address venueRegistry_,
        address assetRegistry_,
        address owner_,
        // Optional; the owner may set the beneficiary before unlock.
        // forge-lint: disable-next-line(missing-zero-check)
        address beneficiary_,
        uint64 unlockTime_
    ) AgenticFacilityBase(factory_, LOCKER, venueRegistry_, assetRegistry_, owner_) {
        beneficiary = beneficiary_;
        unlockTime = unlockTime_;
    }

    /// @inheritdoc ILockerFacility
    /// @dev Gated-only: anyone may unlock after `unlockTime`; the recipient is
    /// the fixed agent beneficiary or the active migration target. LOCKER has
    /// no public-asset path.
    function unlock(address token, address to, uint256 amount) external override nonReentrant {
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < unlockTime) revert UnlockTimeNotReached(unlockTime);
        if (to != beneficiary && !_isActiveMigrationTarget(to)) {
            revert UnlockRecipientNotBeneficiary(to, beneficiary);
        }
        _checkGatedRecipient(token, to);
        emit Unlocked(token, to, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc ILockerFacility
    /// @dev Only increases the unlock time before maturity. Once `unlockTime`
    /// is reached the lock is final; otherwise the owner could keep extending
    /// and deny the fixed beneficiary indefinitely.
    function extend(uint64 newUnlockTime) external override onlyOwner {
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= unlockTime) revert UnlockTimeReached(unlockTime);
        if (newUnlockTime <= unlockTime) revert UnlockTimeNotExtended(unlockTime, newUnlockTime);
        unlockTime = newUnlockTime;
        emit UnlockTimeExtended(newUnlockTime);
    }

    /// @inheritdoc ILockerFacility
    /// @dev Before unlock; agent-only, never a facility.
    function setBeneficiary(address beneficiary_) external override onlyOwner {
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= unlockTime) revert UnlockTimeReached(unlockTime);
        if (beneficiary_ == address(0)) revert ZeroBeneficiary();
        _requireAgent(beneficiary_);
        beneficiary = beneficiary_;
        emit BeneficiarySet(beneficiary_);
    }

    /// @inheritdoc ICustodyFacility
    /// @dev Not part of the LOCKER surface; always reverts.
    function release(address, address, uint256) external pure override {
        revert ReleaseNotSupported();
    }

    /// @inheritdoc ICustodyFacility
    /// @dev Not part of the LOCKER surface; always reverts.
    function releaseNative(address payable, uint256) external pure override {
        revert NativeNotSupported();
    }
}
