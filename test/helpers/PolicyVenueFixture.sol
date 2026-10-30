// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {
    ESCROW,
    FacilityCategory,
    GAME,
    LAUNCH,
    NPM,
    POOL,
    TREASURY,
    TransferKind,
    VAULT
} from "../../contracts/common/Types.sol";
import {AgenticPolicy} from "../../contracts/policy/AgenticPolicy.sol";
import {AgenticVenueRegistry} from "../../contracts/registry/AgenticVenueRegistry.sol";

import {MockFacility} from "../mocks/MockFacility.sol";
import {MockFacilityFactory} from "../mocks/MockFacilityFactory.sol";
import {MockIdentityAdapter} from "../mocks/MockIdentityAdapter.sol";
import {MockIdentityAdapterRegistry} from "../mocks/MockIdentityAdapterRegistry.sol";
import {MockVenueAccount} from "../mocks/MockVenueAccount.sol";

/// @notice Shared valid policy/venue fixture for the AgenticPolicy unit and fuzz tests.
abstract contract PolicyVenueFixture is Test {
    AgenticVenueRegistry internal venue;
    AgenticPolicy internal policy;
    MockFacilityFactory internal facilityFactory;
    MockIdentityAdapter internal identityAdapter;
    MockIdentityAdapterRegistry internal identityRegistry;

    address internal agent = address(0xA11CE);
    address internal agent2 = address(0xB0B);
    address internal nonAgent = address(0xBAD);
    address internal projectOwner = address(0xF00D);

    MockVenueAccount internal pool;
    MockVenueAccount internal lpManager;
    MockVenueAccount internal feeRecipient;
    MockFacility internal vault;
    MockFacility internal game;

    bytes32 internal constant AGENT_ID_KIND = keccak256("AGENT_ID");

    function _deployPolicyVenue() internal {
        venue = new AgenticVenueRegistry(address(this));

        venue.addTypeCategory(POOL, FacilityCategory.POOL);
        venue.addTypeCategory(NPM, FacilityCategory.LP_MANAGER);
        venue.addTypeCategory(TREASURY, FacilityCategory.FEE_RECIPIENT);
        venue.addTypeCategory(VAULT, FacilityCategory.CUSTODY);
        venue.addTypeCategory(LAUNCH, FacilityCategory.CUSTODY);
        venue.addTypeCategory(GAME, FacilityCategory.PURPOSE);
        venue.addTypeCategory(ESCROW, FacilityCategory.PURPOSE);

        facilityFactory = new MockFacilityFactory(address(0));

        venue.setRegistrar(address(this), FacilityCategory.POOL, true);
        venue.setRegistrar(address(this), FacilityCategory.LP_MANAGER, true);
        venue.setRegistrar(address(this), FacilityCategory.FEE_RECIPIENT, true);
        venue.setRegistrar(address(facilityFactory), FacilityCategory.CUSTODY, true);
        venue.setRegistrar(address(facilityFactory), FacilityCategory.PURPOSE, true);

        pool = new MockVenueAccount();
        lpManager = new MockVenueAccount();
        feeRecipient = new MockVenueAccount();
        venue.registerFacility(address(pool), POOL);
        venue.registerFacility(address(lpManager), NPM);
        venue.registerFacility(address(feeRecipient), TREASURY);

        vault = _createFacility(VAULT, projectOwner);
        game = _createFacility(GAME, projectOwner);

        identityRegistry = new MockIdentityAdapterRegistry();
        identityAdapter = new MockIdentityAdapter(AGENT_ID_KIND, 1, 97);
        identityRegistry.setAdapter(AGENT_ID_KIND, address(identityAdapter));
        identityAdapter.setHasIdentity(agent, true);
        identityAdapter.setHasIdentity(agent2, true);

        policy = new AgenticPolicy(address(identityRegistry), address(venue));
    }

    function _createFacility(bytes32 kind, address owner_) internal returns (MockFacility facility) {
        facility = MockFacility(facilityFactory.createFacility(kind, abi.encode(owner_)));
        vm.prank(address(facilityFactory));
        venue.registerFacility(address(facility), kind);
    }

    function _transfer(address from, address to) internal view returns (bool allowed, bytes32 reason) {
        return policy.canTransfer(address(0x1234), from, to, address(0x9999), abi.encode(TransferKind.TRANSFER));
    }

    function _isKnownPolicyVenueAddress(address account) internal view returns (bool) {
        return account == address(this) || account == address(venue) || account == address(policy)
            || account == address(facilityFactory) || account == address(identityAdapter)
            || account == address(identityRegistry) || account == address(pool) || account == address(lpManager)
            || account == address(feeRecipient) || account == address(vault) || account == address(game)
            || account == agent || account == agent2 || account == nonAgent || account == projectOwner;
    }
}
