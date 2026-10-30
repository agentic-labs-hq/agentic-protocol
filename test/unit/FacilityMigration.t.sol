// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ESCROW, FacilityCategory, GAME, LAUNCH, LENDING, LOCKER, VAULT} from "../../contracts/common/Types.sol";
import {AgenticFacilityBase} from "../../contracts/facility/AgenticFacilityBase.sol";
import {AgenticEscrowFacility} from "../../contracts/facility/AgenticEscrowFacility.sol";
import {AgenticGameFacility} from "../../contracts/facility/AgenticGameFacility.sol";
import {AgenticLaunchFacility} from "../../contracts/facility/AgenticLaunchFacility.sol";
import {AgenticLendingFacility} from "../../contracts/facility/AgenticLendingFacility.sol";
import {AgenticLockerFacility} from "../../contracts/facility/AgenticLockerFacility.sol";
import {AgenticVaultFacility} from "../../contracts/facility/AgenticVaultFacility.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";

import {MockVenueRegistry} from "../mocks/MockVenueRegistry.sol";
import {AgenticFacilityBaseHarness} from "../mocks/AgenticFacilityBaseHarness.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {MockTransferPolicy} from "../mocks/MockTransferPolicy.sol";
import {FacilityFixture} from "../helpers/FacilityFixture.sol";

contract FacilityMigrationTest is FacilityFixture {
    function setUp() public {
        _deployFacilities();
    }

    function _migrateSuccess(address facility, address replacement) internal {
        vm.prank(projectOwner);
        FacilityBaseMigrate(facility).migrate(replacement);
    }

    function testVaultMigrateRequiresRevocation() public {
        AgenticVaultFacility old = _createVault(projectOwner);
        AgenticVaultFacility replacement = _createVault(projectOwner);
        _fundVault(old, 1_000 ether);

        vm.prank(projectOwner);
        vm.expectRevert(AgenticFacilityBase.FacilityNotRevoked.selector);
        old.migrate(address(replacement));
    }

    function testVaultMigrateRequiresRegistryReplacement() public {
        AgenticVaultFacility old = _createVault(projectOwner);
        AgenticVaultFacility replacement = _createVault(projectOwner);
        _fundVault(old, 1_000 ether);
        _revoke(address(old));

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticFacilityBase.NotRegistryReplacement.selector, address(0), address(replacement)
            )
        );
        old.migrate(address(replacement));
    }

    function testVaultMigrateRejectsWrongTargetSelfAndZero() public {
        AgenticVaultFacility old = _createVault(projectOwner);
        AgenticVaultFacility replacement = _createVault(projectOwner);
        AgenticVaultFacility other = _createVault(projectOwner);
        _fundVault(old, 1_000 ether);
        _revoke(address(old));
        _setReplacement(address(old), address(replacement));

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticFacilityBase.NotRegistryReplacement.selector, address(replacement), address(other)
            )
        );
        old.migrate(address(other));

        vm.prank(projectOwner);
        vm.expectRevert(AgenticFacilityBase.ReplacementIsSelf.selector);
        old.migrate(address(old));

        vm.prank(projectOwner);
        vm.expectRevert(AgenticFacilityBase.ZeroAddress.selector);
        old.migrate(address(0));
    }

    function testVaultMigrateRejectsInactiveReplacement() public {
        AgenticVaultFacility old = _createVault(projectOwner);
        AgenticVaultFacility replacement = _createVault(projectOwner);
        _fundVault(old, 1_000 ether);
        _revoke(address(old));
        _setReplacement(address(old), address(replacement));
        _revoke(address(replacement));

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.ReplacementNotActive.selector, address(replacement)));
        old.migrate(address(replacement));
    }

    function testVaultMigrateOnlyOwner() public {
        AgenticVaultFacility old = _createVault(projectOwner);
        AgenticVaultFacility replacement = _createVault(projectOwner);
        _fundVault(old, 1_000 ether);
        _revoke(address(old));
        _setReplacement(address(old), address(replacement));

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, agent));
        old.migrate(address(replacement));
    }

    function testVaultMigrateSetsTargetWithoutMovingAssets() public {
        AgenticVaultFacility old = _createVault(projectOwner);
        AgenticVaultFacility replacement = _createVault(projectOwner);
        AgenticToken token = _fundVault(old, 1_000 ether);
        MockToken publicToken = new MockToken();
        publicToken.mint(address(old), 5 ether);
        vm.deal(address(old), 2 ether);

        _revoke(address(old));
        _setReplacement(address(old), address(replacement));
        _migrateSuccess(address(old), address(replacement));

        assertEq(old.migrationTarget(), address(replacement));
        assertEq(token.balanceOf(address(old)), 1_000 ether);
        assertEq(token.balanceOf(address(replacement)), 0);
        assertEq(publicToken.balanceOf(address(old)), 5 ether);
        assertEq(address(old).balance, 2 ether);
        assertEq(address(replacement).balance, 0);
    }

    function testVaultTargetExceptionOnlyAfterMigrateAndWhileActive() public {
        AgenticVaultFacility old = _createVault(projectOwner);
        AgenticVaultFacility replacement = _createVault(projectOwner);
        AgenticVaultFacility replacement2 = _createVault(projectOwner);
        AgenticToken token = _fundVault(old, 1_000 ether);
        _revoke(address(old));
        _setReplacement(address(old), address(replacement));

        // The replacement is a facility and cannot receive gated before migrate.
        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticFacilityBase.FacilityRecipientNotAllowed.selector, address(replacement))
        );
        old.release(address(token), address(replacement), 100 ether);

        _migrateSuccess(address(old), address(replacement));

        vm.prank(projectOwner);
        old.release(address(token), address(replacement), 100 ether);
        assertEq(token.balanceOf(address(replacement)), 100 ether);

        // Re-pointing the registry replacement turns the old target exception off.
        _setReplacement(address(old), address(replacement2));
        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticFacilityBase.FacilityRecipientNotAllowed.selector, address(replacement))
        );
        old.release(address(token), address(replacement), 100 ether);

        // Re-pointing the target requires a new owner-only migrate call.
        _migrateSuccess(address(old), address(replacement2));
        vm.prank(projectOwner);
        old.release(address(token), address(replacement2), 100 ether);
        assertEq(token.balanceOf(address(replacement2)), 100 ether);
    }

    function testVaultMigrateDoesNotMoveNativeOrPublicTokens() public {
        AgenticVaultFacility old = _createVault(projectOwner);
        AgenticVaultFacility replacement = _createVault(projectOwner);
        MockToken publicToken = new MockToken();
        publicToken.mint(address(old), 5 ether);
        vm.deal(address(old), 2 ether);

        _revoke(address(old));
        _setReplacement(address(old), address(replacement));
        _migrateSuccess(address(old), address(replacement));

        assertEq(publicToken.balanceOf(address(old)), 5 ether);
        assertEq(publicToken.balanceOf(address(replacement)), 0);
        assertEq(address(old).balance, 2 ether);
        assertEq(address(replacement).balance, 0);

        // Public asset movement remains a separate owner action.
        vm.prank(projectOwner);
        old.releaseNative(payable(projectOwner), 2 ether);
        assertEq(projectOwner.balance, 2 ether);
    }

    function testVaultPermissiveTokenPolicyStillCannotSendToUnmigratedFacility() public {
        AgenticVaultFacility old = _createVault(projectOwner);
        AgenticVaultFacility replacement = _createVault(projectOwner);
        MockTransferPolicy permissive = new MockTransferPolicy();
        permissive.setPermissive(true);
        policyRegistry.addPolicy(address(permissive), 2);
        AgenticToken plainToken = _gatedToWithPolicy(address(old), address(permissive), 100 ether);

        _revoke(address(old));
        _setReplacement(address(old), address(replacement));

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticFacilityBase.FacilityRecipientNotAllowed.selector, address(replacement))
        );
        old.release(address(plainToken), address(replacement), 1 ether);

        _migrateSuccess(address(old), address(replacement));
        vm.prank(projectOwner);
        old.release(address(plainToken), address(replacement), 1 ether);
        assertEq(plainToken.balanceOf(address(replacement)), 1 ether);
    }

    function testLaunchMigrateReleaseToTarget() public {
        AgenticLaunchFacility old = _createLaunch(projectOwner, projectOwner, agent);
        AgenticLaunchFacility replacement = _createLaunch(projectOwner, projectOwner, agent);
        AgenticToken token = _fundLaunch(old, 1_000 ether);
        _revoke(address(old));
        _setReplacement(address(old), address(replacement));
        _migrateSuccess(address(old), address(replacement));

        vm.prank(projectOwner);
        old.release(address(token), address(replacement), 400 ether);
        assertEq(token.balanceOf(address(replacement)), 400 ether);
    }

    function testLaunchClosedMigrationStillReachesTarget() public {
        AgenticLaunchFacility old = _createLaunch(projectOwner, projectOwner, agent);
        AgenticLaunchFacility replacement = _createLaunch(projectOwner, projectOwner, agent);
        AgenticToken token = _fundLaunch(old, 1_000 ether);
        vm.prank(projectOwner);
        old.close();

        _revoke(address(old));
        _setReplacement(address(old), address(replacement));
        _migrateSuccess(address(old), address(replacement));

        vm.prank(projectOwner);
        old.release(address(token), address(replacement), 100 ether);
        assertEq(token.balanceOf(address(replacement)), 100 ether);
    }

    function testLockerMigrateUnlockToTargetAfterTime() public {
        AgenticLockerFacility old = _createLocker(projectOwner, agent, DEFAULT_UNLOCK_TIME);
        AgenticLockerFacility replacement = _createLocker(projectOwner, agent, DEFAULT_UNLOCK_TIME);
        AgenticToken token = _fundLocker(old, 1_000 ether);
        _revoke(address(old));
        _setReplacement(address(old), address(replacement));
        _migrateSuccess(address(old), address(replacement));

        vm.prank(nonAgent);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticLockerFacility.UnlockTimeNotReached.selector, DEFAULT_UNLOCK_TIME)
        );
        old.unlock(address(token), address(replacement), 1 ether);

        vm.warp(DEFAULT_UNLOCK_TIME);
        vm.prank(nonAgent);
        old.unlock(address(token), address(replacement), 400 ether);
        assertEq(token.balanceOf(address(replacement)), 400 ether);
    }

    function testGameMigrateOwnerSetsOperatorToItselfAndReleasesToTarget() public {
        AgenticGameFacility old = _createGame(projectOwner, address(0));
        AgenticGameFacility replacement = _createGame(projectOwner, projectOwner);
        AgenticToken token = _fundGame(old, 1_000 ether);
        _revoke(address(old));
        _setReplacement(address(old), address(replacement));
        _migrateSuccess(address(old), address(replacement));

        vm.prank(projectOwner);
        old.setOperator(projectOwner);

        vm.prank(projectOwner);
        old.release(address(token), address(replacement), 300 ether);
        assertEq(token.balanceOf(address(replacement)), 300 ether);
    }

    function testEscrowMigrateArbiterReleasesToTarget() public {
        AgenticEscrowFacility old = _createEscrow(projectOwner, address(0), agent, agent);
        AgenticEscrowFacility replacement = _createEscrow(projectOwner, projectOwner, agent, agent);
        AgenticToken token = _gatedToAgent(agent, 1_000 ether);
        vm.prank(agent);
        token.approve(address(old), type(uint256).max);
        vm.prank(agent);
        old.deposit(address(token), 500 ether);

        _revoke(address(old));
        _setReplacement(address(old), address(replacement));
        _migrateSuccess(address(old), address(replacement));

        vm.prank(projectOwner);
        old.setArbiter(projectOwner);

        vm.prank(projectOwner);
        old.release(address(token), address(replacement), 500 ether);
        assertEq(token.balanceOf(address(replacement)), 500 ether);
    }

    function testLendingMigrateKeeperLiquidatesToTarget() public {
        AgenticLendingFacility old = _createLending(projectOwner, address(0), address(0), agent, agent2);
        AgenticLendingFacility replacement = _createLending(projectOwner, projectOwner, projectOwner, agent, agent2);
        AgenticToken token = _gatedToAgent(agent, 1_000 ether);
        vm.prank(agent);
        token.approve(address(old), type(uint256).max);
        vm.prank(agent);
        old.deposit(address(token), 500 ether);

        _revoke(address(old));
        _setReplacement(address(old), address(replacement));
        _migrateSuccess(address(old), address(replacement));

        vm.prank(projectOwner);
        old.setKeeper(projectOwner);

        vm.prank(projectOwner);
        old.liquidate(address(token), address(replacement), 500 ether);
        assertEq(token.balanceOf(address(replacement)), 500 ether);
    }

    // ------------------------------------------------------- base guard harness

    function _harness() internal returns (AgenticFacilityBaseHarness harness, MockVenueRegistry mockVenue) {
        mockVenue = new MockVenueRegistry();
        harness = new AgenticFacilityBaseHarness(
            address(0xBEEF), VAULT, address(mockVenue), address(assetRegistry), projectOwner
        );
        mockVenue.setFacilityForTest(address(harness), FacilityCategory.CUSTODY, VAULT, true);
        mockVenue.setRevokedForTest(address(harness), true);
    }

    function testBaseMigrateRejectsWrongCategoryWithPermissiveVenue() public {
        (AgenticFacilityBaseHarness harness, MockVenueRegistry mockVenue) = _harness();
        address target = address(0xCAFE);
        mockVenue.setFacilityForTest(target, FacilityCategory.PURPOSE, GAME, true);
        mockVenue.setReplacementForTest(address(harness), target);

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticFacilityBase.ReplacementCategoryMismatch.selector,
                target,
                FacilityCategory.CUSTODY,
                FacilityCategory.PURPOSE
            )
        );
        harness.migrate(target);
    }

    function testBaseMigrateRejectsWrongTypeWithPermissiveVenue() public {
        (AgenticFacilityBaseHarness harness, MockVenueRegistry mockVenue) = _harness();
        address target = address(0xCAFE);
        mockVenue.setFacilityForTest(target, FacilityCategory.CUSTODY, LOCKER, true);
        mockVenue.setReplacementForTest(address(harness), target);

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticFacilityBase.ReplacementTypeMismatch.selector, target, VAULT, LOCKER)
        );
        harness.migrate(target);
    }

    function testBaseMigrateRejectsInactiveWithPermissiveVenue() public {
        (AgenticFacilityBaseHarness harness, MockVenueRegistry mockVenue) = _harness();
        address target = address(0xCAFE);
        mockVenue.setFacilityForTest(target, FacilityCategory.CUSTODY, VAULT, false);
        mockVenue.setReplacementForTest(address(harness), target);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.ReplacementNotActive.selector, target));
        harness.migrate(target);
    }

    function testBaseMigrateSetsTargetWithPermissiveVenue() public {
        (AgenticFacilityBaseHarness harness, MockVenueRegistry mockVenue) = _harness();
        address target = address(0xCAFE);
        mockVenue.setFacilityForTest(target, FacilityCategory.CUSTODY, VAULT, true);
        mockVenue.setReplacementForTest(address(harness), target);

        vm.prank(projectOwner);
        harness.migrate(target);
        assertEq(harness.migrationTarget(), target);
    }
}

/// @dev Minimal local view of the migrate selector for fixture helpers.
interface FacilityBaseMigrate {
    function migrate(address replacement) external;
}
