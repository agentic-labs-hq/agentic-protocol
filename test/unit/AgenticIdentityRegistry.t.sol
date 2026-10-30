// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {AgenticIdentityRegistry} from "../../contracts/identity/AgenticIdentityRegistry.sol";
import {AGENT_ID_KIND} from "../../contracts/identity/IAgentIdRegistry.sol";
import {MockIdentityAdapter} from "../helpers/IdentityTestMocks.sol";

contract AgenticIdentityRegistryTest is Test {
    uint256 internal constant MAX_ADAPTERS = 4;
    bytes32 internal constant OTHER_KIND = keccak256("OTHER");

    AgenticIdentityRegistry internal registry;
    MockIdentityAdapter internal agentIdAdapter;
    MockIdentityAdapter internal otherAdapter;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    event AdapterRegistered(address indexed adapter, bytes32 indexed kind);
    event AdapterReplaced(address indexed oldAdapter, address indexed newAdapter, bytes32 indexed kind);
    event AdapterDisabled(address indexed adapter, bytes32 indexed kind);
    event GovernanceTransferStarted(address indexed current, address indexed pending);
    event GovernanceTransferred(address indexed previous, address indexed newGovernance);

    function setUp() public {
        registry = new AgenticIdentityRegistry(MAX_ADAPTERS);
        agentIdAdapter = new MockIdentityAdapter(AGENT_ID_KIND);
        otherAdapter = new MockIdentityAdapter(OTHER_KIND);
    }

    function testConstructorState() public view {
        assertEq(registry.maxAdapters(), MAX_ADAPTERS);
        assertEq(registry.governance(), address(this));
        assertEq(registry.pendingGovernance(), address(0));
        assertEq(registry.enabledAdapters().length, 0);
    }

    function testConstructorRejectsZeroMax() public {
        vm.expectRevert(AgenticIdentityRegistry.InvalidMaxAdapters.selector);
        new AgenticIdentityRegistry(0);
    }

    function testRegisterAdapter() public {
        vm.expectEmit(true, true, false, true, address(registry));
        emit AdapterRegistered(address(agentIdAdapter), AGENT_ID_KIND);
        registry.registerAdapter(address(agentIdAdapter), AGENT_ID_KIND);

        assertTrue(registry.isEnabled(address(agentIdAdapter)));
        assertEq(registry.adapterOf(AGENT_ID_KIND), address(agentIdAdapter));
        address[] memory adapters = registry.enabledAdapters();
        assertEq(adapters.length, 1);
        assertEq(adapters[0], address(agentIdAdapter));
    }

    function testRegisterOnlyGovernance() public {
        vm.prank(ALICE);
        vm.expectRevert(AgenticIdentityRegistry.NotGovernance.selector);
        registry.registerAdapter(address(agentIdAdapter), AGENT_ID_KIND);
    }

    function testRegisterRejectsZeroAdapter() public {
        vm.expectRevert(AgenticIdentityRegistry.InvalidAdapter.selector);
        registry.registerAdapter(address(0), AGENT_ID_KIND);
    }

    function testRegisterRejectsCodelessAdapter() public {
        vm.expectRevert(AgenticIdentityRegistry.AdapterNotContract.selector);
        registry.registerAdapter(ALICE, AGENT_ID_KIND);
    }

    function testRegisterRejectsZeroKind() public {
        vm.expectRevert(AgenticIdentityRegistry.InvalidKind.selector);
        registry.registerAdapter(address(agentIdAdapter), bytes32(0));
    }

    function testRegisterRejectsKindMismatch() public {
        vm.expectRevert(
            abi.encodeWithSelector(AgenticIdentityRegistry.KindMismatch.selector, AGENT_ID_KIND, OTHER_KIND)
        );
        registry.registerAdapter(address(otherAdapter), AGENT_ID_KIND);
    }

    function testRegisterRejectsDuplicateKind() public {
        registry.registerAdapter(address(agentIdAdapter), AGENT_ID_KIND);

        MockIdentityAdapter sameKind = new MockIdentityAdapter(AGENT_ID_KIND);
        vm.expectRevert(abi.encodeWithSelector(AgenticIdentityRegistry.KindAlreadyRegistered.selector, AGENT_ID_KIND));
        registry.registerAdapter(address(sameKind), AGENT_ID_KIND);
    }

    function testRegisterRejectsDuplicateAdapter() public {
        registry.registerAdapter(address(agentIdAdapter), AGENT_ID_KIND);

        vm.expectRevert(
            abi.encodeWithSelector(AgenticIdentityRegistry.AdapterAlreadyRegistered.selector, address(agentIdAdapter))
        );
        registry.registerAdapter(address(agentIdAdapter), OTHER_KIND);
    }

    function testRegisterRespectsMaxAdapters() public {
        AgenticIdentityRegistry capped = new AgenticIdentityRegistry(2);
        MockIdentityAdapter first = new MockIdentityAdapter(keccak256("K1"));
        MockIdentityAdapter second = new MockIdentityAdapter(keccak256("K2"));
        MockIdentityAdapter third = new MockIdentityAdapter(keccak256("K3"));

        capped.registerAdapter(address(first), first.kind());
        capped.registerAdapter(address(second), second.kind());

        bytes32 thirdKind = third.kind();
        vm.expectRevert(abi.encodeWithSelector(AgenticIdentityRegistry.MaxAdaptersReached.selector, 2));
        capped.registerAdapter(address(third), thirdKind);
    }

    function testReplaceAdapter() public {
        registry.registerAdapter(address(agentIdAdapter), AGENT_ID_KIND);
        MockIdentityAdapter replacement = new MockIdentityAdapter(AGENT_ID_KIND);

        vm.expectEmit(true, true, true, true, address(registry));
        emit AdapterReplaced(address(agentIdAdapter), address(replacement), AGENT_ID_KIND);
        registry.replaceAdapter(address(replacement));

        assertFalse(registry.isEnabled(address(agentIdAdapter)));
        assertTrue(registry.isEnabled(address(replacement)));
        assertEq(registry.adapterOf(AGENT_ID_KIND), address(replacement));

        address[] memory adapters = registry.enabledAdapters();
        assertEq(adapters.length, 1);
        assertEq(adapters[0], address(replacement));
    }

    function testReplacePreservesArrayPosition() public {
        registry.registerAdapter(address(agentIdAdapter), AGENT_ID_KIND);
        registry.registerAdapter(address(otherAdapter), OTHER_KIND);
        MockIdentityAdapter replacement = new MockIdentityAdapter(AGENT_ID_KIND);

        registry.replaceAdapter(address(replacement));

        address[] memory adapters = registry.enabledAdapters();
        assertEq(adapters.length, 2);
        assertEq(adapters[0], address(replacement));
        assertEq(adapters[1], address(otherAdapter));
    }

    function testReplaceOnlyGovernance() public {
        registry.registerAdapter(address(agentIdAdapter), AGENT_ID_KIND);
        MockIdentityAdapter replacement = new MockIdentityAdapter(AGENT_ID_KIND);

        vm.prank(ALICE);
        vm.expectRevert(AgenticIdentityRegistry.NotGovernance.selector);
        registry.replaceAdapter(address(replacement));
    }

    function testReplaceRejectsUnknownKind() public {
        MockIdentityAdapter replacement = new MockIdentityAdapter(OTHER_KIND);

        vm.expectRevert(abi.encodeWithSelector(AgenticIdentityRegistry.NoAdapterForKind.selector, OTHER_KIND));
        registry.replaceAdapter(address(replacement));
    }

    function testReplaceRejectsZeroAdapter() public {
        vm.expectRevert(AgenticIdentityRegistry.InvalidAdapter.selector);
        registry.replaceAdapter(address(0));
    }

    function testReplaceRejectsCodelessAdapter() public {
        vm.expectRevert(AgenticIdentityRegistry.AdapterNotContract.selector);
        registry.replaceAdapter(ALICE);
    }

    function testReplaceRejectsSameAdapter() public {
        registry.registerAdapter(address(agentIdAdapter), AGENT_ID_KIND);

        vm.expectRevert(
            abi.encodeWithSelector(AgenticIdentityRegistry.AdapterAlreadyEnabled.selector, address(agentIdAdapter))
        );
        registry.replaceAdapter(address(agentIdAdapter));
    }

    function testMaxAdaptersAfterReplace() public {
        AgenticIdentityRegistry capped = new AgenticIdentityRegistry(2);
        MockIdentityAdapter first = new MockIdentityAdapter(keccak256("K1"));
        MockIdentityAdapter second = new MockIdentityAdapter(keccak256("K2"));
        MockIdentityAdapter replacement = new MockIdentityAdapter(keccak256("K1"));
        MockIdentityAdapter third = new MockIdentityAdapter(keccak256("K3"));

        capped.registerAdapter(address(first), first.kind());
        capped.registerAdapter(address(second), second.kind());
        capped.replaceAdapter(address(replacement));

        bytes32 thirdKind = third.kind();
        vm.expectRevert(abi.encodeWithSelector(AgenticIdentityRegistry.MaxAdaptersReached.selector, 2));
        capped.registerAdapter(address(third), thirdKind);
    }

    function testDisableAdapter() public {
        registry.registerAdapter(address(agentIdAdapter), AGENT_ID_KIND);
        registry.registerAdapter(address(otherAdapter), OTHER_KIND);

        vm.expectEmit(true, true, false, true, address(registry));
        emit AdapterDisabled(address(agentIdAdapter), AGENT_ID_KIND);
        registry.disableAdapter(address(agentIdAdapter));

        assertFalse(registry.isEnabled(address(agentIdAdapter)));
        assertEq(registry.adapterOf(AGENT_ID_KIND), address(0));

        address[] memory adapters = registry.enabledAdapters();
        assertEq(adapters.length, 1);
        assertEq(adapters[0], address(otherAdapter));
    }

    function testDisableOnlyGovernance() public {
        registry.registerAdapter(address(agentIdAdapter), AGENT_ID_KIND);
        registry.registerAdapter(address(otherAdapter), OTHER_KIND);

        vm.prank(ALICE);
        vm.expectRevert(AgenticIdentityRegistry.NotGovernance.selector);
        registry.disableAdapter(address(agentIdAdapter));
    }

    function testDisableRejectsNotEnabled() public {
        registry.registerAdapter(address(agentIdAdapter), AGENT_ID_KIND);

        vm.expectRevert(
            abi.encodeWithSelector(AgenticIdentityRegistry.AdapterNotEnabled.selector, address(otherAdapter))
        );
        registry.disableAdapter(address(otherAdapter));
    }

    function testDisableRejectsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticIdentityRegistry.AdapterNotEnabled.selector, address(0)));
        registry.disableAdapter(address(0));
    }

    function testDisableLastAdapterReverts() public {
        registry.registerAdapter(address(agentIdAdapter), AGENT_ID_KIND);

        vm.expectRevert(AgenticIdentityRegistry.LastAdapter.selector);
        registry.disableAdapter(address(agentIdAdapter));
    }

    function testDisableThenReRegister() public {
        registry.registerAdapter(address(agentIdAdapter), AGENT_ID_KIND);
        registry.registerAdapter(address(otherAdapter), OTHER_KIND);
        registry.disableAdapter(address(agentIdAdapter));

        registry.registerAdapter(address(agentIdAdapter), AGENT_ID_KIND);

        assertTrue(registry.isEnabled(address(agentIdAdapter)));
        assertEq(registry.adapterOf(AGENT_ID_KIND), address(agentIdAdapter));
        assertEq(registry.enabledAdapters().length, 2);
    }

    function testDisableKeepsOtherAdapters() public {
        MockIdentityAdapter third = new MockIdentityAdapter(keccak256("THIRD"));
        registry.registerAdapter(address(agentIdAdapter), AGENT_ID_KIND);
        registry.registerAdapter(address(otherAdapter), OTHER_KIND);
        registry.registerAdapter(address(third), third.kind());

        registry.disableAdapter(address(otherAdapter));

        address[] memory adapters = registry.enabledAdapters();
        assertEq(adapters.length, 2);
        assertTrue(_contains(adapters, address(agentIdAdapter)));
        assertTrue(_contains(adapters, address(third)));
        assertFalse(_contains(adapters, address(otherAdapter)));
    }

    function testEnabledAdaptersReturnsCopy() public {
        registry.registerAdapter(address(agentIdAdapter), AGENT_ID_KIND);

        address[] memory copy = registry.enabledAdapters();
        copy[0] = ALICE;

        assertEq(registry.enabledAdapters()[0], address(agentIdAdapter));
    }

    function testGovernanceTransferTwoStep() public {
        vm.expectEmit(true, true, false, true, address(registry));
        emit GovernanceTransferStarted(address(this), ALICE);
        registry.transferGovernance(ALICE);

        assertEq(registry.governance(), address(this));
        assertEq(registry.pendingGovernance(), ALICE);

        // Current governance remains in control until the pending one accepts.
        registry.registerAdapter(address(agentIdAdapter), AGENT_ID_KIND);

        vm.expectEmit(true, true, false, true, address(registry));
        emit GovernanceTransferred(address(this), ALICE);
        vm.prank(ALICE);
        registry.acceptGovernance();

        assertEq(registry.governance(), ALICE);
        assertEq(registry.pendingGovernance(), address(0));

        // Old governance has no power; the new one does.
        MockIdentityAdapter newAdapter = new MockIdentityAdapter(OTHER_KIND);
        vm.expectRevert(AgenticIdentityRegistry.NotGovernance.selector);
        registry.registerAdapter(address(newAdapter), OTHER_KIND);

        vm.prank(ALICE);
        registry.registerAdapter(address(newAdapter), OTHER_KIND);
        assertTrue(registry.isEnabled(address(newAdapter)));
    }

    function testTransferGovernanceOnlyGovernance() public {
        vm.prank(ALICE);
        vm.expectRevert(AgenticIdentityRegistry.NotGovernance.selector);
        registry.transferGovernance(BOB);
    }

    function testTransferGovernanceRejectsZero() public {
        vm.expectRevert(AgenticIdentityRegistry.InvalidGovernance.selector);
        registry.transferGovernance(address(0));
    }

    function testTransferGovernanceRejectsSameGovernance() public {
        vm.expectRevert(AgenticIdentityRegistry.InvalidGovernance.selector);
        registry.transferGovernance(address(this));
    }

    function testAcceptGovernanceOnlyPending() public {
        vm.prank(ALICE);
        vm.expectRevert(AgenticIdentityRegistry.NotPendingGovernance.selector);
        registry.acceptGovernance();
    }

    function testPendingGovernanceCanBeOverwritten() public {
        registry.transferGovernance(ALICE);
        registry.transferGovernance(BOB);
        assertEq(registry.pendingGovernance(), BOB);

        vm.prank(ALICE);
        vm.expectRevert(AgenticIdentityRegistry.NotPendingGovernance.selector);
        registry.acceptGovernance();

        vm.prank(BOB);
        registry.acceptGovernance();
        assertEq(registry.governance(), BOB);
    }

    function _contains(address[] memory haystack, address needle) internal pure returns (bool) {
        for (uint256 i = 0; i < haystack.length; i++) {
            if (haystack[i] == needle) return true;
        }
        return false;
    }
}
