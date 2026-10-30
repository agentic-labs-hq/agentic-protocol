// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {FacilityCategory, POOL, VAULT} from "../../contracts/common/Types.sol";
import {Governance2Step} from "../../contracts/common/Governance2Step.sol";
import {AgenticPolicyRegistry} from "../../contracts/policy/AgenticPolicyRegistry.sol";
import {AgenticVenueRegistry} from "../../contracts/registry/AgenticVenueRegistry.sol";
import {MockFacility} from "../mocks/MockFacility.sol";
import {MockFacilityFactory} from "../mocks/MockFacilityFactory.sol";
import {MockPolicy} from "../mocks/MockPolicy.sol";

contract RegistryFuzzTest is Test {
    AgenticVenueRegistry internal venue;
    MockFacilityFactory internal factory;

    address internal projectOwner = address(0xF00D);

    function setUp() public {
        venue = new AgenticVenueRegistry(address(this));
        factory = new MockFacilityFactory(address(0));
    }

    function testFuzzAddTypeCategoryAppendOnly(bytes32 kind, uint8 raw1, uint8 raw2) public {
        vm.assume(kind != bytes32(0));
        FacilityCategory first = FacilityCategory(bound(raw1, 1, 5));
        FacilityCategory second = FacilityCategory(bound(raw2, 1, 5));

        venue.addTypeCategory(kind, first);
        vm.expectRevert(abi.encodeWithSelector(AgenticVenueRegistry.TypeAlreadyMapped.selector, kind, first));
        venue.addTypeCategory(kind, second);
        assertEq(uint256(venue.categoryOfType(kind)), uint256(first));
    }

    function testFuzzSetRegistrarRequiresCode(address account) public {
        vm.assume(account != address(0));
        vm.assume(account.code.length == 0);
        vm.expectRevert(abi.encodeWithSelector(AgenticVenueRegistry.AccountHasNoCode.selector, account));
        venue.setRegistrar(account, FacilityCategory.POOL, true);
    }

    function testFuzzNonGovernanceCannotMutateVenue(address caller) public {
        vm.assume(caller != address(this));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, caller));
        venue.addTypeCategory(keccak256("FUZZ_KIND"), FacilityCategory.POOL);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, caller));
        venue.setRegistrar(address(this), FacilityCategory.POOL, true);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, caller));
        venue.revokeFacility(address(this));
    }

    function testFuzzReplacementOnlyActiveSameCategorySubtype(address replacement) public {
        venue.addTypeCategory(VAULT, FacilityCategory.CUSTODY);
        venue.setRegistrar(address(factory), FacilityCategory.CUSTODY, true);

        MockFacility first = MockFacility(factory.createFacility(VAULT, abi.encode(projectOwner)));
        vm.prank(address(factory));
        venue.registerFacility(address(first), VAULT);
        venue.revokeFacility(address(first));

        vm.prank(projectOwner);
        (bool ok,) =
            address(venue).call(abi.encodeCall(AgenticVenueRegistry.setReplacement, (address(first), replacement)));

        if (ok) {
            assertTrue(venue.isFacility(replacement));
            assertTrue(replacement != address(first));
            assertEq(uint256(venue.facilityCategory(replacement)), uint256(FacilityCategory.CUSTODY));
            assertEq(venue.facilityType(replacement), VAULT);
        }
    }

    function testFuzzPolicyRegistryCap(uint8 rawCount) public {
        uint256 cap = 3;
        AgenticPolicyRegistry registry = new AgenticPolicyRegistry(address(this), cap);
        uint256 count = bound(rawCount, 0, cap + 2);

        for (uint256 i = 0; i < count; ++i) {
            MockPolicy policy = new MockPolicy(i);
            if (i < cap) {
                registry.addPolicy(address(policy), i + 1);
            } else {
                vm.expectRevert(abi.encodeWithSelector(AgenticPolicyRegistry.PolicyCapReached.selector, cap));
                registry.addPolicy(address(policy), i + 1);
            }
        }
    }

    function testFuzzPolicyVersionUnique(uint256 version) public {
        vm.assume(version != 0);
        AgenticPolicyRegistry registry = new AgenticPolicyRegistry(address(this), 3);
        MockPolicy first = new MockPolicy(1);
        MockPolicy second = new MockPolicy(2);

        registry.addPolicy(address(first), version);
        vm.expectRevert(abi.encodeWithSelector(AgenticPolicyRegistry.VersionAlreadyUsed.selector, version));
        registry.addPolicy(address(second), version);
    }

    function testFuzzPolicyRegistryNonGovernance(address caller) public {
        vm.assume(caller != address(this));
        AgenticPolicyRegistry registry = new AgenticPolicyRegistry(address(this), 3);
        MockPolicy policy = new MockPolicy(1);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, caller));
        registry.addPolicy(address(policy), 1);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, caller));
        registry.setCurrentPolicy(address(policy));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, caller));
        registry.deprecatePolicy(address(policy));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, caller));
        registry.transferGovernance(caller);
    }
}
