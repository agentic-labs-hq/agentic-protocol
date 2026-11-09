// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NFT_VAULT} from "../common/Types.sol";
import {INFTCustodyFacility, INFTVaultFacility} from "../interfaces/INFTCustodyFacility.sol";
import {AgenticNFTFacilityBase} from "./AgenticNFTFacilityBase.sol";

/// @notice CUSTODY/NFT_VAULT: project NFT treasury (INTERFACES v2.3 §NFT).
/// @dev Funded by mint only, because the policy denies agent -> CUSTODY. The
/// owner releases a held token id to an agent (or the active migration target).
/// There is no public release and no facility recipient outside migration.
contract AgenticNFTVaultFacility is AgenticNFTFacilityBase, INFTVaultFacility {
    /// @param factory_ The NFT facility factory stamp; the factory's deployment helper enforces the caller.
    /// @param venueRegistry_ Venue registry for migration validation.
    /// @param nftRegistry_ NFT registry used to classify gated collections.
    /// @param owner_ Project owner (no Agent ID required).
    constructor(address factory_, address venueRegistry_, address nftRegistry_, address owner_)
        AgenticNFTFacilityBase(factory_, NFT_VAULT, venueRegistry_, nftRegistry_, owner_)
    {}

    /// @inheritdoc INFTCustodyFacility
    /// @dev Owner-only. A gated collection may only go to an agent or the active
    /// migration target. A non-gated collection may go to any non-zero recipient.
    function release(address collection, uint256 tokenId, address to) external override nonReentrant onlyOwner {
        _checkNFTOutflow(collection, tokenId, to);
        emit NFTReleased(collection, tokenId, to);
        _sendNFT(collection, to, tokenId);
    }

    /// @inheritdoc INFTCustodyFacility
    /// @dev Diamond resolution: the base implements the body, the interface
    /// declares the selector. Both modifiers are re-applied here because an
    /// overriding function does not inherit them.
    function migrateTokens(address collection, uint256[] calldata tokenIds)
        external
        override(AgenticNFTFacilityBase, INFTCustodyFacility)
        onlyOwner
        nonReentrant
    {
        _migrateTokens(collection, tokenIds);
    }
}
