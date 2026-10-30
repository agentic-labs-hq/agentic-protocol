// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    ESCROW,
    FacilityCategory,
    GAME,
    LAUNCH,
    LENDING,
    LOCKER,
    NPM,
    POOL,
    TREASURY,
    VAULT
} from "../../contracts/common/Types.sol";
import {AgenticFacilityFactory} from "../../contracts/facility/AgenticFacilityFactory.sol";
import {AgenticEscrowFacility} from "../../contracts/facility/AgenticEscrowFacility.sol";
import {AgenticGameFacility} from "../../contracts/facility/AgenticGameFacility.sol";
import {AgenticLaunchFacility} from "../../contracts/facility/AgenticLaunchFacility.sol";
import {AgenticLendingFacility} from "../../contracts/facility/AgenticLendingFacility.sol";
import {AgenticLockerFacility} from "../../contracts/facility/AgenticLockerFacility.sol";
import {AgenticVaultFacility} from "../../contracts/facility/AgenticVaultFacility.sol";
import {AgenticVenueRegistry} from "../../contracts/registry/AgenticVenueRegistry.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";

import {MockProxyFacility} from "../mocks/MockProxyFacility.sol";
import {FacilityFixture} from "../helpers/FacilityFixture.sol";

contract AgenticFacilityFactoryTest is FacilityFixture {
    bytes32 internal constant UNKNOWN_KIND = keccak256("UNKNOWN");

    function setUp() public {
        _deployFacilities();
    }

    function testFactoryPolicyAndVenueWiring() public view {
        assertEq(facilities.policy(), address(policy));
        assertEq(facilities.venueRegistry(), address(venue));
        assertEq(facilities.assetRegistry(), address(assetRegistry));
        assertTrue(facilities.isSupportedType(VAULT));
        assertTrue(facilities.isSupportedType(LAUNCH));
        assertTrue(facilities.isSupportedType(LOCKER));
        assertTrue(facilities.isSupportedType(GAME));
        assertTrue(facilities.isSupportedType(ESCROW));
        assertTrue(facilities.isSupportedType(LENDING));
        assertFalse(facilities.isSupportedType(POOL));
        assertFalse(facilities.isSupportedType(NPM));
        assertFalse(facilities.isSupportedType(TREASURY));
        assertFalse(facilities.isSupportedType(UNKNOWN_KIND));
    }

    function testFactoryCanonicalCodehashExistsForEachKind() public view {
        assertTrue(facilities.codehashOf(VAULT) != bytes32(0));
        assertTrue(facilities.codehashOf(LAUNCH) != bytes32(0));
        assertTrue(facilities.codehashOf(LOCKER) != bytes32(0));
        assertTrue(facilities.codehashOf(GAME) != bytes32(0));
        assertTrue(facilities.codehashOf(ESCROW) != bytes32(0));
        assertTrue(facilities.codehashOf(LENDING) != bytes32(0));
        assertEq(facilities.codehashOf(UNKNOWN_KIND), bytes32(0));
    }

    function testFactoryIsPermissionlessAndRegisters() public {
        vm.prank(nonAgent);
        AgenticVaultFacility vault =
            AgenticVaultFacility(payable(facilities.createFacility(VAULT, abi.encode(projectOwner))));

        assertEq(vault.factory(), address(facilities));
        assertEq(vault.facilityType(), VAULT);
        assertEq(vault.owner(), projectOwner);
        assertTrue(venue.isFacility(address(vault)));
        assertTrue(venue.isFacilityOfCategory(address(vault), FacilityCategory.CUSTODY));
        assertTrue(venue.isFacilityOfType(address(vault), VAULT));
        assertEq(venue.factoryOf(address(vault)), address(facilities));
        assertEq(uint8(venue.facilityCategory(address(vault))), uint8(FacilityCategory.CUSTODY));
        assertEq(address(vault).codehash, facilities.codehashOf(VAULT));
    }

    function testFactoryOwnerMayBeProjectWithoutAgentId() public {
        assertFalse(policy.isMember(projectOwner));
        AgenticVaultFacility vault = _createVault(projectOwner);
        assertEq(vault.owner(), projectOwner);
    }

    function testFactoryCreatesEverySupportedKindWithRoles() public {
        AgenticVaultFacility vault = _createVault(projectOwner);
        AgenticLaunchFacility launch = _createLaunch(projectOwner, projectOwner, agent);
        AgenticLockerFacility locker = _createLocker(projectOwner, agent, DEFAULT_UNLOCK_TIME);
        AgenticGameFacility game = _createGame(projectOwner, projectOwner);
        AgenticEscrowFacility escrow = _createEscrow(projectOwner, projectOwner, agent, agent);
        AgenticLendingFacility lending = _createLending(projectOwner, projectOwner, projectOwner, agent, agent2);

        assertEq(vault.facilityType(), VAULT);
        assertEq(launch.facilityType(), LAUNCH);
        assertEq(locker.facilityType(), LOCKER);
        assertEq(game.facilityType(), GAME);
        assertEq(escrow.facilityType(), ESCROW);
        assertEq(lending.facilityType(), LENDING);

        assertEq(uint8(venue.facilityCategory(address(vault))), uint8(FacilityCategory.CUSTODY));
        assertEq(uint8(venue.facilityCategory(address(launch))), uint8(FacilityCategory.CUSTODY));
        assertEq(uint8(venue.facilityCategory(address(locker))), uint8(FacilityCategory.CUSTODY));
        assertEq(uint8(venue.facilityCategory(address(game))), uint8(FacilityCategory.PURPOSE));
        assertEq(uint8(venue.facilityCategory(address(escrow))), uint8(FacilityCategory.PURPOSE));
        assertEq(uint8(venue.facilityCategory(address(lending))), uint8(FacilityCategory.PURPOSE));

        assertEq(launch.operator(), projectOwner);
        assertEq(launch.beneficiary(), agent);
        assertEq(locker.beneficiary(), agent);
        assertEq(locker.unlockTime(), DEFAULT_UNLOCK_TIME);
        assertEq(game.operator(), projectOwner);
        assertEq(escrow.arbiter(), projectOwner);
        assertEq(escrow.beneficiary(), agent);
        assertEq(escrow.depositor(), agent);
        assertEq(lending.keeper(), projectOwner);
        assertEq(lending.oracle(), projectOwner);
        assertEq(lending.lender(), agent);
        assertEq(lending.borrower(), agent2);
    }

    function testFactoryAllowsZeroOptionalRoles() public {
        AgenticLaunchFacility launch = _createLaunch(projectOwner, address(0), address(0));
        AgenticLockerFacility locker = _createLocker(projectOwner, address(0), DEFAULT_UNLOCK_TIME);
        AgenticGameFacility game = _createGame(projectOwner, address(0));
        AgenticEscrowFacility escrow = _createEscrow(projectOwner, address(0), address(0), address(0));
        AgenticLendingFacility lending = _createLending(projectOwner, address(0), address(0), address(0), address(0));

        assertEq(launch.operator(), address(0));
        assertEq(launch.beneficiary(), address(0));
        assertEq(locker.beneficiary(), address(0));
        assertEq(game.operator(), address(0));
        assertEq(escrow.arbiter(), address(0));
        assertEq(escrow.beneficiary(), address(0));
        assertEq(escrow.depositor(), address(0));
        assertEq(lending.keeper(), address(0));
        assertEq(lending.oracle(), address(0));
        assertEq(lending.lender(), address(0));
        assertEq(lending.borrower(), address(0));
    }

    function testFactoryRejectsUnsupportedKinds() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.UnsupportedFacilityType.selector, POOL));
        facilities.createFacility(POOL, abi.encode(projectOwner));

        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.UnsupportedFacilityType.selector, NPM));
        facilities.createFacility(NPM, abi.encode(projectOwner));

        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.UnsupportedFacilityType.selector, UNKNOWN_KIND));
        facilities.createFacility(UNKNOWN_KIND, abi.encode(projectOwner));
    }

    function testFactoryRejectsZeroOwnerForEachKind() public {
        bytes memory zeroOwner = abi.encode(address(0));

        vm.expectRevert(AgenticFacilityFactory.InvalidOwner.selector);
        facilities.createFacility(VAULT, zeroOwner);

        vm.expectRevert(AgenticFacilityFactory.InvalidOwner.selector);
        facilities.createFacility(LAUNCH, abi.encode(address(0), address(0), address(0)));

        vm.expectRevert(AgenticFacilityFactory.InvalidOwner.selector);
        facilities.createFacility(LOCKER, abi.encode(address(0), address(0), uint64(0)));

        vm.expectRevert(AgenticFacilityFactory.InvalidOwner.selector);
        facilities.createFacility(GAME, abi.encode(address(0), address(0)));

        vm.expectRevert(AgenticFacilityFactory.InvalidOwner.selector);
        facilities.createFacility(ESCROW, abi.encode(address(0), address(0), address(0), address(0)));

        vm.expectRevert(AgenticFacilityFactory.InvalidOwner.selector);
        facilities.createFacility(LENDING, abi.encode(address(0), address(0), address(0), address(0), address(0)));
    }

    function testFactoryRejectsNonAgentBeneficiaries() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.AgentRequired.selector, nonAgent));
        facilities.createFacility(LAUNCH, abi.encode(projectOwner, projectOwner, nonAgent));

        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.AgentRequired.selector, nonAgent));
        facilities.createFacility(LOCKER, abi.encode(projectOwner, nonAgent, DEFAULT_UNLOCK_TIME));

        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.AgentRequired.selector, nonAgent));
        facilities.createFacility(ESCROW, abi.encode(projectOwner, projectOwner, nonAgent, agent));
    }

    function testFactoryRejectsNonAgentDepositorLenderBorrower() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.AgentRequired.selector, nonAgent));
        facilities.createFacility(ESCROW, abi.encode(projectOwner, projectOwner, agent, nonAgent));

        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.AgentRequired.selector, nonAgent));
        facilities.createFacility(LENDING, abi.encode(projectOwner, projectOwner, projectOwner, nonAgent, agent2));

        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.AgentRequired.selector, nonAgent));
        facilities.createFacility(LENDING, abi.encode(projectOwner, projectOwner, projectOwner, agent, nonAgent));
    }

    function testFactoryRejectsFacilityAsAgentRole() public {
        AgenticVaultFacility vault = _createVault(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.FacilityNotAgent.selector, address(vault)));
        facilities.createFacility(LAUNCH, abi.encode(projectOwner, projectOwner, address(vault)));

        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.FacilityNotAgent.selector, address(vault)));
        facilities.createFacility(ESCROW, abi.encode(projectOwner, projectOwner, agent, address(vault)));

        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.FacilityNotAgent.selector, address(vault)));
        facilities.createFacility(LENDING, abi.encode(projectOwner, projectOwner, projectOwner, address(vault), agent2));
    }

    function testFactoryRejectsRevokedFacilityWithAgentIdAsBeneficiary() public {
        AgenticVaultFacility revoked = _createVault(projectOwner);
        identityAdapter.setHasIdentity(address(revoked), true);
        _revoke(address(revoked));

        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.FacilityNotAgent.selector, address(revoked)));
        facilities.createFacility(LAUNCH, abi.encode(projectOwner, projectOwner, address(revoked)));
    }

    function testFactoryRejectsMalformedInitData() public {
        vm.expectRevert();
        facilities.createFacility(VAULT, hex"1234");

        vm.expectRevert();
        facilities.createFacility(LAUNCH, abi.encode(projectOwner));
    }

    function testFactorySameKindFacilitiesShareCodehash() public {
        AgenticVaultFacility first = _createVault(projectOwner);
        AgenticVaultFacility second = _createVault(agent);

        assertEq(address(first).codehash, address(second).codehash);
        assertEq(address(first).codehash, facilities.codehashOf(VAULT));
        assertEq(address(second).codehash, facilities.codehashOf(VAULT));
    }

    function testFactorySameKindCodehashForEveryKind() public {
        AgenticVaultFacility vault1 = _createVault(projectOwner);
        AgenticVaultFacility vault2 = _createVault(agent);
        assertEq(address(vault1).codehash, address(vault2).codehash);

        AgenticLaunchFacility launch1 = _createLaunch(projectOwner, projectOwner, agent);
        AgenticLaunchFacility launch2 = _createLaunch(agent, agent, agent2);
        assertEq(address(launch1).codehash, address(launch2).codehash);

        AgenticLockerFacility locker1 = _createLocker(projectOwner, agent, DEFAULT_UNLOCK_TIME);
        AgenticLockerFacility locker2 = _createLocker(agent, agent2, DEFAULT_UNLOCK_TIME + 1);
        assertEq(address(locker1).codehash, address(locker2).codehash);

        AgenticGameFacility game1 = _createGame(projectOwner, projectOwner);
        AgenticGameFacility game2 = _createGame(agent, agent);
        assertEq(address(game1).codehash, address(game2).codehash);

        AgenticEscrowFacility escrow1 = _createEscrow(projectOwner, projectOwner, agent, agent);
        AgenticEscrowFacility escrow2 = _createEscrow(agent, agent, agent2, agent2);
        assertEq(address(escrow1).codehash, address(escrow2).codehash);

        AgenticLendingFacility lending1 = _createLending(projectOwner, projectOwner, projectOwner, agent, agent2);
        AgenticLendingFacility lending2 = _createLending(agent, agent, agent, agent2, agent);
        assertEq(address(lending1).codehash, address(lending2).codehash);
    }

    function testFactoryDifferentKindsHaveDifferentCodehash() public {
        AgenticVaultFacility vault = _createVault(projectOwner);
        AgenticGameFacility game = _createGame(projectOwner, projectOwner);
        assertTrue(address(vault).codehash != address(game).codehash);
    }

    function testFactoryAllKindsMatchCanonicalCodehash() public {
        assertEq(address(_createVault(projectOwner)).codehash, facilities.codehashOf(VAULT));
        assertEq(address(_createLaunch(projectOwner, projectOwner, agent)).codehash, facilities.codehashOf(LAUNCH));
        assertEq(
            address(_createLocker(projectOwner, agent, DEFAULT_UNLOCK_TIME)).codehash, facilities.codehashOf(LOCKER)
        );
        assertEq(address(_createGame(projectOwner, projectOwner)).codehash, facilities.codehashOf(GAME));
        assertEq(
            address(_createEscrow(projectOwner, projectOwner, agent, agent)).codehash, facilities.codehashOf(ESCROW)
        );
        assertEq(
            address(_createLending(projectOwner, projectOwner, projectOwner, agent, agent2)).codehash,
            facilities.codehashOf(LENDING)
        );
    }

    function testRegistryRejectsProxyFacilityCodehash() public {
        MockProxyFacility proxy = new MockProxyFacility(address(facilities), VAULT, projectOwner);
        vm.prank(address(facilities));
        vm.expectPartialRevert(AgenticVenueRegistry.CodehashMismatch.selector);
        venue.registerFacility(address(proxy), VAULT);
    }

    function testFactoryCodehashIncludesFactoryAddress() public {
        AgenticFacilityFactory.TemplateDeployers memory deployers = AgenticFacilityFactory.TemplateDeployers({
            vault: facilities.vaultDeployer(),
            launch: facilities.launchDeployer(),
            locker: facilities.lockerDeployer(),
            game: facilities.gameDeployer(),
            escrow: facilities.escrowDeployer(),
            lending: facilities.lendingDeployer()
        });
        AgenticFacilityFactory second = AgenticFacilityFactory(
            vm.deployCode(
                "AgenticFacilityFactory.sol:AgenticFacilityFactory",
                abi.encode(address(policy), address(venue), address(assetRegistry), deployers)
            )
        );
        venue.setRegistrar(address(second), FacilityCategory.CUSTODY, true);
        venue.setRegistrar(address(second), FacilityCategory.PURPOSE, true);

        AgenticVaultFacility firstVault = _createVault(projectOwner);
        AgenticVaultFacility secondVault =
            AgenticVaultFacility(payable(second.createFacility(VAULT, abi.encode(projectOwner))));

        assertTrue(address(firstVault).codehash != address(secondVault).codehash);
        assertEq(address(secondVault).codehash, second.codehashOf(VAULT));
        assertEq(secondVault.factory(), address(second));
    }

    function testFactoryRegistrationRequiresRegistrar() public {
        AgenticFacilityFactory.TemplateDeployers memory deployers = AgenticFacilityFactory.TemplateDeployers({
            vault: facilities.vaultDeployer(),
            launch: facilities.launchDeployer(),
            locker: facilities.lockerDeployer(),
            game: facilities.gameDeployer(),
            escrow: facilities.escrowDeployer(),
            lending: facilities.lendingDeployer()
        });
        AgenticFacilityFactory unregistered = AgenticFacilityFactory(
            vm.deployCode(
                "AgenticFacilityFactory.sol:AgenticFacilityFactory",
                abi.encode(address(policy), address(venue), address(assetRegistry), deployers)
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticVenueRegistry.NotRegistrar.selector, address(unregistered), FacilityCategory.CUSTODY
            )
        );
        unregistered.createFacility(VAULT, abi.encode(projectOwner));
    }

    function testFactoryRejectsZeroDeployer() public {
        AgenticFacilityFactory.TemplateDeployers memory deployers = AgenticFacilityFactory.TemplateDeployers({
            vault: address(0),
            launch: facilities.launchDeployer(),
            locker: facilities.lockerDeployer(),
            game: facilities.gameDeployer(),
            escrow: facilities.escrowDeployer(),
            lending: facilities.lendingDeployer()
        });
        vm.expectRevert(AgenticFacilityFactory.ZeroAddress.selector);
        vm.deployCode(
            "AgenticFacilityFactory.sol:AgenticFacilityFactory",
            abi.encode(address(policy), address(venue), address(assetRegistry), deployers)
        );
    }

    function testFactoryRejectsZeroAssetRegistry() public {
        AgenticFacilityFactory.TemplateDeployers memory deployers = AgenticFacilityFactory.TemplateDeployers({
            vault: facilities.vaultDeployer(),
            launch: facilities.launchDeployer(),
            locker: facilities.lockerDeployer(),
            game: facilities.gameDeployer(),
            escrow: facilities.escrowDeployer(),
            lending: facilities.lendingDeployer()
        });
        vm.expectRevert(AgenticFacilityFactory.ZeroAddress.selector);
        vm.deployCode(
            "AgenticFacilityFactory.sol:AgenticFacilityFactory",
            abi.encode(address(policy), address(venue), address(0), deployers)
        );
    }

    function testFactoryRejectsCodelessAssetRegistry() public {
        AgenticFacilityFactory.TemplateDeployers memory deployers = AgenticFacilityFactory.TemplateDeployers({
            vault: facilities.vaultDeployer(),
            launch: facilities.launchDeployer(),
            locker: facilities.lockerDeployer(),
            game: facilities.gameDeployer(),
            escrow: facilities.escrowDeployer(),
            lending: facilities.lendingDeployer()
        });
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.RegistryHasNoCode.selector, nonAgent));
        vm.deployCode(
            "AgenticFacilityFactory.sol:AgenticFacilityFactory",
            abi.encode(address(policy), address(venue), nonAgent, deployers)
        );
    }

    function testFactoryRejectsCodelessDeployer() public {
        AgenticFacilityFactory.TemplateDeployers memory deployers = AgenticFacilityFactory.TemplateDeployers({
            vault: nonAgent,
            launch: facilities.launchDeployer(),
            locker: facilities.lockerDeployer(),
            game: facilities.gameDeployer(),
            escrow: facilities.escrowDeployer(),
            lending: facilities.lendingDeployer()
        });
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.DeployerHasNoCode.selector, nonAgent));
        vm.deployCode(
            "AgenticFacilityFactory.sol:AgenticFacilityFactory",
            abi.encode(address(policy), address(venue), address(assetRegistry), deployers)
        );
    }

    function testFactoryNeverHoldsTokens() public {
        AgenticVaultFacility vault = _createVault(projectOwner);
        AgenticToken token = _fundVault(vault, 1 ether);
        assertEq(token.balanceOf(address(vault)), 1 ether);
        assertEq(token.balanceOf(address(facilities)), 0);
        assertEq(address(facilities).balance, 0);
        // The factory is not itself a facility.
        assertEq(policy.isFacility(address(facilities)), false);
    }
}
