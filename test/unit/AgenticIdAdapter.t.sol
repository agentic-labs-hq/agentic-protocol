// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {AgenticIdAdapter} from "../../contracts/identity/AgenticIdAdapter.sol";
import {AGENT_ID_KIND, IAgentIdRegistry} from "../../contracts/identity/IAgentIdRegistry.sol";
import {MockAgentId} from "../../contracts/identity/mocks/MockAgentId.sol";
import {
    EmptyHandleAgentIdRegistry,
    RevertingAgentIdRegistry,
    ZeroBalanceAgentIdRegistry
} from "../helpers/IdentityTestMocks.sol";

contract AgenticIdAdapterTest is Test {
    MockAgentId internal registry;
    AgenticIdAdapter internal adapter;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    string internal constant HANDLE = "test-agent-handle";

    function setUp() public {
        registry = new MockAgentId();
        adapter = new AgenticIdAdapter(registry);
    }

    function testKindIsAgentIdKind() public view {
        assertEq(adapter.kind(), AGENT_ID_KIND);
        assertEq(adapter.kind(), keccak256("AGENT_ID"));
    }

    function testVersion() public view {
        assertEq(adapter.version(), 1);
    }

    function testChainId() public view {
        assertEq(adapter.chainId(), block.chainid);
    }

    function testConstructorRejectsZeroRegistry() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticIdAdapter.InvalidRegistry.selector, address(0)));
        new AgenticIdAdapter(IAgentIdRegistry(address(0)));
    }

    function testConstructorRejectsCodelessRegistry() public {
        address eoa = address(0x1234);
        vm.expectRevert(abi.encodeWithSelector(AgenticIdAdapter.InvalidRegistry.selector, eoa));
        new AgenticIdAdapter(IAgentIdRegistry(eoa));
    }

    function testValidIdentity() public {
        registry.setIdentity(ALICE, HANDLE);

        assertTrue(adapter.hasIdentity(ALICE));

        bytes32 expectedHash = keccak256(bytes(HANDLE));
        (uint256 tokenId, bytes32 handleHash) = adapter.identityOf(ALICE);
        assertEq(tokenId, uint256(expectedHash));
        assertEq(handleHash, expectedHash);
    }

    function testRequireIdentityValid() public {
        registry.setIdentity(ALICE, HANDLE);

        (uint256 tokenId, bytes32 handleHash) = adapter.requireIdentity(ALICE);
        assertEq(tokenId, uint256(keccak256(bytes(HANDLE))));
        assertEq(handleHash, keccak256(bytes(HANDLE)));
    }

    function testZeroWalletIsIneligible() public {
        // Even a misbehaving registry that reports a balance for address(0)
        // must not make the zero wallet eligible.
        registry.setRaw(address(0), 1, HANDLE, address(0));

        assertFalse(adapter.hasIdentity(address(0)));
        (uint256 tokenId, bytes32 handleHash) = adapter.identityOf(address(0));
        assertEq(tokenId, 0);
        assertEq(handleHash, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(AgenticIdAdapter.NotAgent.selector, address(0)));
        adapter.requireIdentity(address(0));
    }

    function testZeroWalletShortCircuitsBeforeRegistry() public {
        RevertingAgentIdRegistry reverting = new RevertingAgentIdRegistry();
        AgenticIdAdapter zeroSafe = new AgenticIdAdapter(reverting);

        // A registry call for address(0) would revert; the adapter must not call it.
        assertFalse(zeroSafe.hasIdentity(address(0)));
    }

    function testNoBalanceIsIneligible() public {
        registry.setRaw(ALICE, 0, HANDLE, ALICE);

        assertFalse(adapter.hasIdentity(ALICE));
        (uint256 tokenId, bytes32 handleHash) = adapter.identityOf(ALICE);
        assertEq(tokenId, 0);
        assertEq(handleHash, bytes32(0));
    }

    function testEmptyHandleIsIneligible() public {
        registry.setRaw(ALICE, 1, "", ALICE);

        assertFalse(adapter.hasIdentity(ALICE));
    }

    function testWrongHandleOwnerIsIneligible() public {
        registry.setRaw(ALICE, 1, HANDLE, BOB);

        assertFalse(adapter.hasIdentity(ALICE));
    }

    function testBalanceGreaterThanOneIsEligible() public {
        registry.setRaw(ALICE, 5, HANDLE, ALICE);

        assertTrue(adapter.hasIdentity(ALICE));
    }

    function testIneligibleWalletsReturnZeroIdentity() public {
        registry.setRaw(ALICE, 1, HANDLE, BOB);

        (uint256 tokenId, bytes32 handleHash) = adapter.identityOf(ALICE);
        assertEq(tokenId, 0);
        assertEq(handleHash, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(AgenticIdAdapter.NotAgent.selector, ALICE));
        adapter.requireIdentity(ALICE);
    }

    function testLiveReadsNoCache() public {
        registry.setIdentity(ALICE, HANDLE);
        assertTrue(adapter.hasIdentity(ALICE));

        registry.clear(ALICE);
        assertFalse(adapter.hasIdentity(ALICE));

        registry.setIdentity(ALICE, "alice2");
        assertTrue(adapter.hasIdentity(ALICE));

        (uint256 tokenId, bytes32 handleHash) = adapter.identityOf(ALICE);
        assertEq(handleHash, keccak256(bytes("alice2")));
        assertEq(tokenId, uint256(handleHash));
    }

    function testHandleChangeChangesDerivation() public {
        registry.setIdentity(ALICE, "first");
        bytes32 firstHash = keccak256(bytes("first"));
        (uint256 firstId,) = adapter.identityOf(ALICE);
        assertEq(firstId, uint256(firstHash));

        registry.setIdentity(ALICE, "second");
        bytes32 secondHash = keccak256(bytes("second"));
        (uint256 secondId,) = adapter.identityOf(ALICE);
        assertEq(secondId, uint256(secondHash));
        assertTrue(firstId != secondId);
    }

    function testMultipleWallets() public {
        registry.setIdentity(ALICE, "alice");
        registry.setIdentity(BOB, "bob");

        assertTrue(adapter.hasIdentity(ALICE));
        assertTrue(adapter.hasIdentity(BOB));

        (uint256 aliceId,) = adapter.identityOf(ALICE);
        (uint256 bobId,) = adapter.identityOf(BOB);
        assertEq(aliceId, uint256(keccak256(bytes("alice"))));
        assertEq(bobId, uint256(keccak256(bytes("bob"))));
        assertTrue(aliceId != bobId);
    }

    function testNoBalanceDoesNotReadHandle() public {
        ZeroBalanceAgentIdRegistry zeroBalance = new ZeroBalanceAgentIdRegistry();
        AgenticIdAdapter shortCircuit = new AgenticIdAdapter(zeroBalance);

        // A handleOf call would revert; the adapter must stop after balanceOf.
        assertFalse(shortCircuit.hasIdentity(ALICE));
    }

    function testEmptyHandleDoesNotReadOwner() public {
        EmptyHandleAgentIdRegistry emptyHandle = new EmptyHandleAgentIdRegistry();
        AgenticIdAdapter shortCircuit = new AgenticIdAdapter(emptyHandle);

        // An ownerOfHandle call would revert; the adapter must stop after the empty handle.
        assertFalse(shortCircuit.hasIdentity(ALICE));
    }

    function testRegistryRevertPropagatesHasIdentity() public {
        RevertingAgentIdRegistry reverting = new RevertingAgentIdRegistry();
        AgenticIdAdapter failClosed = new AgenticIdAdapter(reverting);

        vm.expectRevert(RevertingAgentIdRegistry.RegistryUnavailable.selector);
        failClosed.hasIdentity(ALICE);
    }

    function testRegistryRevertPropagatesIdentityOf() public {
        RevertingAgentIdRegistry reverting = new RevertingAgentIdRegistry();
        AgenticIdAdapter failClosed = new AgenticIdAdapter(reverting);

        vm.expectRevert(RevertingAgentIdRegistry.RegistryUnavailable.selector);
        failClosed.identityOf(ALICE);
    }

    function testRegistryRevertPropagatesRequireIdentity() public {
        RevertingAgentIdRegistry reverting = new RevertingAgentIdRegistry();
        AgenticIdAdapter failClosed = new AgenticIdAdapter(reverting);

        vm.expectRevert(RevertingAgentIdRegistry.RegistryUnavailable.selector);
        failClosed.requireIdentity(ALICE);
    }
}
