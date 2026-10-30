// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

/// @notice Read-only view of the protocol asset registry used by the gated NPM
///.
/// @dev 0.7.6 ABI mirror: the NPM only calls these two selectors. It does not
/// import the 0.8.20 protocol interface, so no cross-version struct is shared.
interface IGatedAssetRegistry {
    function isRegistered(address asset) external view returns (bool);
    function policyOf(address asset) external view returns (address);
}
