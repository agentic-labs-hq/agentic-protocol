// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFacility, IMigratableFacility} from "./IFacility.sol";

/// @notice NFT custody facility interface (INTERFACES v2.3 §NFT).
/// @dev CUSTODY facilities are funded by mint only: the policy denies
/// agent -> CUSTODY, so a project mints directly to the facility and the
/// facility releases to agents.
interface INFTCustodyFacility is IFacility, IMigratableFacility {
    function release(address collection, uint256 tokenId, address to) external;
    function migrateTokens(address collection, uint256[] calldata tokenIds) external;

    event NFTReleased(address indexed collection, uint256 indexed tokenId, address indexed to);
}

/// @notice NFT_VAULT template interface (CUSTODY subtype).
interface INFTVaultFacility is INFTCustodyFacility {}

/// @notice NFT_LAUNCH template interface (CUSTODY subtype).
interface INFTLaunchFacility is INFTCustodyFacility {
    function operator() external view returns (address);
    function beneficiary() external view returns (address);
    function setOperator(address operator) external;
    function setBeneficiary(address beneficiary) external;
    function close() external;
    function closed() external view returns (bool);

    event NFTOperatorSet(address indexed operator);
    event NFTBeneficiarySet(address indexed beneficiary);
    event NFTClosed();
}

/// @notice NFT_LOCKER template interface (CUSTODY subtype).
interface INFTLockerFacility is INFTCustodyFacility {
    function beneficiary() external view returns (address);
    function unlockTime() external view returns (uint64);
    function setBeneficiary(address beneficiary) external;
    function extend(uint64 newUnlockTime) external;
    function unlock(address collection, uint256 tokenId, address to) external;

    event NFTBeneficiarySet(address indexed beneficiary);
    event NFTUnlockTimeExtended(uint64 newUnlockTime);
    event NFTUnlocked(address indexed collection, uint256 indexed tokenId, address indexed to);
}
