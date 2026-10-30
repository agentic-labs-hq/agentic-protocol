// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IIdentityAdapter} from "../../contracts/interfaces/IIdentityAdapter.sol";
import {IAgentIdRegistry} from "../../contracts/identity/IAgentIdRegistry.sol";

/// @notice Identity adapter test double with a configurable kind.
contract MockIdentityAdapter is IIdentityAdapter {
    bytes32 private immutable _kind;

    constructor(bytes32 kind_) {
        _kind = kind_;
    }

    function hasIdentity(address) external pure override returns (bool) {
        return false;
    }

    function identityOf(address) external pure override returns (uint256, bytes32) {
        return (0, bytes32(0));
    }

    function requireIdentity(address) external pure override returns (uint256, bytes32) {
        return (0, bytes32(0));
    }

    function kind() external view override returns (bytes32) {
        return _kind;
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function chainId() external pure override returns (uint256) {
        return 1;
    }
}

/// @notice Registry whose reads always revert, to prove fail-closed behavior.
contract RevertingAgentIdRegistry is IAgentIdRegistry {
    error RegistryUnavailable();

    function balanceOf(address) external pure override returns (uint256) {
        revert RegistryUnavailable();
    }

    function handleOf(address) external pure override returns (string memory) {
        revert RegistryUnavailable();
    }

    function ownerOfHandle(string calldata) external pure override returns (address) {
        revert RegistryUnavailable();
    }
}

/// @notice Registry with a zero balance; any further read is a test failure.
contract ZeroBalanceAgentIdRegistry is IAgentIdRegistry {
    error UnexpectedRegistryRead();

    function balanceOf(address) external pure override returns (uint256) {
        return 0;
    }

    function handleOf(address) external pure override returns (string memory) {
        revert UnexpectedRegistryRead();
    }

    function ownerOfHandle(string calldata) external pure override returns (address) {
        revert UnexpectedRegistryRead();
    }
}

/// @notice Registry with a balance but an empty handle; owner read is a test failure.
contract EmptyHandleAgentIdRegistry is IAgentIdRegistry {
    error UnexpectedRegistryRead();

    function balanceOf(address) external pure override returns (uint256) {
        return 1;
    }

    function handleOf(address) external pure override returns (string memory) {
        return "";
    }

    function ownerOfHandle(string calldata) external pure override returns (address) {
        revert UnexpectedRegistryRead();
    }
}
