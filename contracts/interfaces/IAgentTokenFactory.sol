// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Permissionless gated token factory interface.
interface IAgentTokenFactory {
    function policyRegistry() external view returns (address);
    function assetRegistry() external view returns (address);
    function facilityRegistry() external view returns (address);
    function maxRecipients() external view returns (uint256);

    function createToken(
        string calldata name,
        string calldata symbol,
        address policy,
        address[] calldata initialRecipients,
        uint256[] calldata initialAmounts,
        string calldata metadataURI
    ) external returns (address token);

    event TokenCreated(address indexed token, address indexed creator, address indexed policy);
}
