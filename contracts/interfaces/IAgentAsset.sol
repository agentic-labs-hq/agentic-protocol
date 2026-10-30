// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssetType} from "../common/Types.sol";

/// @notice Common gated asset surface.
interface IAgentAsset {
    function policy() external view returns (address);
    function assetType() external view returns (AssetType);
    function creator() external view returns (address);
    function metadataURI() external view returns (string memory);
}

/// @notice Gated FT token surface.
interface IAgentToken is IAgentAsset {
    function factory() external view returns (address);
}
