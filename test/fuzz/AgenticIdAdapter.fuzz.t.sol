// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {AgenticIdAdapter} from "../../contracts/identity/AgenticIdAdapter.sol";
import {MockAgentId} from "../../contracts/identity/mocks/MockAgentId.sol";
import {RevertingAgentIdRegistry, ZeroBalanceAgentIdRegistry} from "../helpers/IdentityTestMocks.sol";

contract AgenticIdAdapterFuzzTest is Test {
    MockAgentId internal registry;
    AgenticIdAdapter internal adapter;

    function setUp() public {
        registry = new MockAgentId();
        adapter = new AgenticIdAdapter(registry);
    }

    function testFuzzEligibleIdentity(address wallet, string memory handle) public {
        vm.assume(wallet != address(0));
        vm.assume(bytes(handle).length > 0 && bytes(handle).length <= 128);

        registry.setIdentity(wallet, handle);

        assertTrue(adapter.hasIdentity(wallet));

        bytes32 expectedHash = keccak256(bytes(handle));
        (uint256 tokenId, bytes32 handleHash) = adapter.identityOf(wallet);
        assertEq(handleHash, expectedHash);
        assertEq(tokenId, uint256(expectedHash));

        (uint256 requiredId, bytes32 requiredHash) = adapter.requireIdentity(wallet);
        assertEq(requiredId, tokenId);
        assertEq(requiredHash, handleHash);
    }

    function testFuzzIneligibleWallet(address wallet) public {
        vm.assume(wallet != address(0));

        assertFalse(adapter.hasIdentity(wallet));

        (uint256 tokenId, bytes32 handleHash) = adapter.identityOf(wallet);
        assertEq(tokenId, 0);
        assertEq(handleHash, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(AgenticIdAdapter.NotAgent.selector, wallet));
        adapter.requireIdentity(wallet);
    }

    function testFuzzWrongHandleOwner(address wallet, address handleOwner, string memory handle) public {
        vm.assume(wallet != address(0));
        vm.assume(handleOwner != wallet);
        vm.assume(bytes(handle).length > 0 && bytes(handle).length <= 128);

        registry.setRaw(wallet, 1, handle, handleOwner);

        assertFalse(adapter.hasIdentity(wallet));
    }

    function testFuzzZeroBalanceShortCircuits(address wallet) public {
        vm.assume(wallet != address(0));

        ZeroBalanceAgentIdRegistry zeroBalance = new ZeroBalanceAgentIdRegistry();
        AgenticIdAdapter shortCircuit = new AgenticIdAdapter(zeroBalance);

        assertFalse(shortCircuit.hasIdentity(wallet));
    }

    function testFuzzFailClosed(address wallet) public {
        vm.assume(wallet != address(0));

        RevertingAgentIdRegistry reverting = new RevertingAgentIdRegistry();
        AgenticIdAdapter failClosed = new AgenticIdAdapter(reverting);

        vm.expectRevert(RevertingAgentIdRegistry.RegistryUnavailable.selector);
        failClosed.hasIdentity(wallet);

        vm.expectRevert(RevertingAgentIdRegistry.RegistryUnavailable.selector);
        failClosed.identityOf(wallet);

        vm.expectRevert(RevertingAgentIdRegistry.RegistryUnavailable.selector);
        failClosed.requireIdentity(wallet);
    }
}
