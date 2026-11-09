// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFacility, IMigratableFacility} from "./IFacility.sol";

/// @notice NFT purpose facility interface (INTERFACES v2.3 §NFT).
/// @dev PURPOSE facilities accept agent deposits (agent -> PURPOSE is allowed
/// by the policy) and release under role control. `consume` is GAME only and
/// locks the token permanently inside the facility.
interface INFTPurposeFacility is IFacility, IMigratableFacility {
    function consume(address collection, uint256 tokenId) external;
    function release(address collection, uint256 tokenId, address to) external;
    function refund(address collection, uint256 tokenId, address to) external;
    function migrateTokens(address collection, uint256[] calldata tokenIds) external;

    event NFTReleased(address indexed collection, uint256 indexed tokenId, address indexed to);
    event NFTRefunded(address indexed collection, uint256 indexed tokenId, address indexed to);
    event NFTConsumed(address indexed collection, uint256 indexed tokenId);
}

/// @notice NFT_GAME template interface (PURPOSE subtype).
interface INFTGameFacility is INFTPurposeFacility {
    function operator() external view returns (address);
    function setOperator(address operator) external;
    function consumed(address collection, uint256 tokenId) external view returns (bool);

    event NFTOperatorSet(address indexed operator);
}

/// @notice NFT_ESCROW template interface (PURPOSE subtype).
interface INFTEscrowFacility is INFTPurposeFacility {
    function arbiter() external view returns (address);
    function beneficiary() external view returns (address);
    function setArbiter(address arbiter) external;
    function setBeneficiary(address beneficiary) external;

    event NFTArbiterSet(address indexed arbiter);
    event NFTBeneficiarySet(address indexed beneficiary);
}
