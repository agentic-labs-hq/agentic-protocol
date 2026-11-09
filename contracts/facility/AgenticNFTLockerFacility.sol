// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NFT_LOCKER} from "../common/Types.sol";
import {INFTCustodyFacility, INFTLockerFacility} from "../interfaces/INFTCustodyFacility.sol";
import {AgenticNFTFacilityBase} from "./AgenticNFTFacilityBase.sol";

/// @notice CUSTODY/NFT_LOCKER: time-locked NFTs for a fixed agent beneficiary
/// (INTERFACES v2.3 §NFT). `unlock` is callable by anyone after `unlockTime`,
/// only to the beneficiary (or the active migration target). `extend` and
/// `setBeneficiary` are owner-only; the beneficiary is agent-only and can only
/// be changed before unlock. `release` always reverts: LOCKER has no generic
/// release path.
contract AgenticNFTLockerFacility is AgenticNFTFacilityBase, INFTLockerFacility {
    /// @inheritdoc INFTLockerFacility
    address public override beneficiary;

    /// @inheritdoc INFTLockerFacility
    uint64 public override unlockTime;

    /// @notice Thrown when the beneficiary is set to zero.
    error ZeroBeneficiary();
    /// @notice Thrown when the unlock time has not been reached.
    error UnlockTimeNotReached(uint64 unlockTime);
    /// @notice Thrown when the unlock recipient is not the beneficiary.
    error UnlockRecipientNotBeneficiary(address recipient, address beneficiary);
    /// @notice Thrown when `extend` does not increase the unlock time.
    error UnlockTimeNotExtended(uint64 currentTime, uint64 newTime);
    /// @notice Thrown when the lock has already matured.
    error UnlockTimeReached(uint64 unlockTime);
    /// @notice Thrown when `release` is called; LOCKER has no generic release.
    error ReleaseNotSupported();

    /// @param factory_ The NFT facility factory stamp; the factory's deployment helper enforces the caller.
    /// @param venueRegistry_ Venue registry for migration validation.
    /// @param nftRegistry_ NFT registry used to classify gated collections.
    /// @param owner_ Project owner (no Agent ID required).
    /// @param beneficiary_ Agent beneficiary (may be zero until owner sets it).
    /// @param unlockTime_ Absolute Unix unlock time.
    constructor(
        address factory_,
        address venueRegistry_,
        address nftRegistry_,
        address owner_,
        // Optional; the owner may set the beneficiary before unlock.
        // forge-lint: disable-next-line(missing-zero-check)
        address beneficiary_,
        uint64 unlockTime_
    ) AgenticNFTFacilityBase(factory_, NFT_LOCKER, venueRegistry_, nftRegistry_, owner_) {
        if (beneficiary_ != address(0)) _requireAgent(beneficiary_);
        beneficiary = beneficiary_;
        unlockTime = unlockTime_;
    }

    /// @inheritdoc INFTLockerFacility
    /// @dev Anyone may unlock after `unlockTime`; the recipient is the fixed
    /// agent beneficiary or the active migration target.
    function unlock(address collection, uint256 tokenId, address to) external override nonReentrant {
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < unlockTime) revert UnlockTimeNotReached(unlockTime);
        if (to != beneficiary && !_isActiveMigrationTarget(to)) {
            revert UnlockRecipientNotBeneficiary(to, beneficiary);
        }
        _checkNFTOutflow(collection, tokenId, to);
        emit NFTUnlocked(collection, tokenId, to);
        _sendNFT(collection, to, tokenId);
    }

    /// @inheritdoc INFTLockerFacility
    /// @dev Only increases the unlock time before maturity. Once `unlockTime`
    /// is reached the lock is final; otherwise the owner could keep extending
    /// and deny the fixed beneficiary indefinitely.
    function extend(uint64 newUnlockTime) external override onlyOwner {
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= unlockTime) revert UnlockTimeReached(unlockTime);
        if (newUnlockTime <= unlockTime) revert UnlockTimeNotExtended(unlockTime, newUnlockTime);
        unlockTime = newUnlockTime;
        emit NFTUnlockTimeExtended(newUnlockTime);
    }

    /// @inheritdoc INFTLockerFacility
    /// @dev Before unlock; agent-only, never a facility.
    function setBeneficiary(address beneficiary_) external override onlyOwner {
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= unlockTime) revert UnlockTimeReached(unlockTime);
        if (beneficiary_ == address(0)) revert ZeroBeneficiary();
        _requireAgent(beneficiary_);
        beneficiary = beneficiary_;
        emit NFTBeneficiarySet(beneficiary_);
    }

    /// @inheritdoc INFTCustodyFacility
    /// @dev Not part of the LOCKER surface; always reverts.
    function release(address, uint256, address) external pure override {
        revert ReleaseNotSupported();
    }

    /// @inheritdoc INFTCustodyFacility
    /// @dev Diamond resolution: the base implements the body, the interface
    /// declares the selector.
    function migrateTokens(address collection, uint256[] calldata tokenIds)
        external
        override(AgenticNFTFacilityBase, INFTCustodyFacility)
        onlyOwner
        nonReentrant
    {
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < unlockTime) revert UnlockTimeNotReached(unlockTime);
        _migrateTokens(collection, tokenIds);
    }
}
