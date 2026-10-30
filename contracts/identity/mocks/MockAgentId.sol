// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAgentIdRegistry} from "../IAgentIdRegistry.sol";

/// @title MockAgentId
/// @notice Testnet/test registry implementing the three Agent ID reads.
/// @dev Test double only; not part of the production deployment. The deployer
/// administers the mock data so tests and testnet demos can mint identities.
contract MockAgentId is IAgentIdRegistry {
    error NotAdmin();

    address public immutable admin;

    mapping(address wallet => uint256 balance) private _balances;
    mapping(address wallet => string handle) private _handles;
    mapping(bytes32 handleHash => address owner) private _handleOwners;

    constructor() {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    /// @inheritdoc IAgentIdRegistry
    function balanceOf(address wallet) external view override returns (uint256) {
        return _balances[wallet];
    }

    /// @inheritdoc IAgentIdRegistry
    function handleOf(address wallet) external view override returns (string memory) {
        return _handles[wallet];
    }

    /// @inheritdoc IAgentIdRegistry
    function ownerOfHandle(string calldata handle) external view override returns (address) {
        return _handleOwners[keccak256(bytes(handle))];
    }

    /// @notice Binds `handle` to `wallet` with a balance of one.
    function setIdentity(address wallet, string calldata handle) external onlyAdmin {
        _set(wallet, 1, handle, wallet);
    }

    /// @notice Sets arbitrary registry state, including ineligible combinations.
    function setRaw(address wallet, uint256 balance, string calldata handle, address handleOwner) external onlyAdmin {
        _set(wallet, balance, handle, handleOwner);
    }

    /// @notice Clears all registry state for `wallet`.
    function clear(address wallet) external onlyAdmin {
        _set(wallet, 0, "", address(0));
    }

    function _set(address wallet, uint256 balance, string memory handle, address handleOwner) private {
        string memory previous = _handles[wallet];
        if (bytes(previous).length != 0) delete _handleOwners[keccak256(bytes(previous))];

        _balances[wallet] = balance;
        _handles[wallet] = handle;
        if (bytes(handle).length != 0) _handleOwners[keccak256(bytes(handle))] = handleOwner;
    }
}
