// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {AgenticIdentityRegistry} from "../../contracts/identity/AgenticIdentityRegistry.sol";
import {MockIdentityAdapter} from "../helpers/IdentityTestMocks.sol";

contract IdentityAdapterRegistryFuzzTest is Test {
    function testFuzzMaxAdaptersCap(uint8 max) public {
        uint256 cap = bound(uint256(max), 1, 8);
        AgenticIdentityRegistry registry = new AgenticIdentityRegistry(cap);

        for (uint256 i = 0; i < cap; i++) {
            MockIdentityAdapter adapter = new MockIdentityAdapter(keccak256(abi.encode("kind", i)));
            registry.registerAdapter(address(adapter), adapter.kind());
        }
        assertEq(registry.enabledAdapters().length, cap);

        MockIdentityAdapter extra = new MockIdentityAdapter(keccak256(abi.encode("extra")));
        bytes32 extraKind = extra.kind();
        vm.expectRevert(abi.encodeWithSelector(AgenticIdentityRegistry.MaxAdaptersReached.selector, cap));
        registry.registerAdapter(address(extra), extraKind);
    }

    function testFuzzRegisterKindMismatch(bytes32 kind, bytes32 adapterKind) public {
        vm.assume(kind != bytes32(0));
        vm.assume(adapterKind != bytes32(0));
        vm.assume(kind != adapterKind);

        AgenticIdentityRegistry registry = new AgenticIdentityRegistry(1);
        MockIdentityAdapter adapter = new MockIdentityAdapter(adapterKind);

        vm.expectRevert(abi.encodeWithSelector(AgenticIdentityRegistry.KindMismatch.selector, kind, adapterKind));
        registry.registerAdapter(address(adapter), kind);
    }

    function testFuzzGovernanceTransfer(address newGovernance) public {
        vm.assume(newGovernance != address(0));
        vm.assume(newGovernance != address(this));

        AgenticIdentityRegistry registry = new AgenticIdentityRegistry(1);
        registry.transferGovernance(newGovernance);

        assertEq(registry.governance(), address(this));
        assertEq(registry.pendingGovernance(), newGovernance);

        vm.prank(newGovernance);
        registry.acceptGovernance();

        assertEq(registry.governance(), newGovernance);
        assertEq(registry.pendingGovernance(), address(0));
    }
}
