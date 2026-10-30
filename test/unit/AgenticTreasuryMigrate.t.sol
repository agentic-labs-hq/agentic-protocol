// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FacilityCategory, TREASURY} from "../../contracts/common/Types.sol";
import {Governance2Step} from "../../contracts/common/Governance2Step.sol";
import {AgenticTreasury} from "../../contracts/treasury/AgenticTreasury.sol";

import {TreasuryFixture} from "../helpers/TreasuryFixture.sol";

/// @notice migration tests. `migrate` records the registry replacement and
/// never moves tokens; governance then uses the one gated `transferToken`
/// exception to move each gated balance.
contract AgenticTreasuryMigrateTest is TreasuryFixture {
    event TreasuryMigrated(address indexed replacement);

    function setUp() public {
        _deployTreasury();
    }

    // ------------------------------------------------------------- migrate

    function testMigrateOnlyGovernance() public {
        _prepareMigration(address(replacement));

        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonGov));
        treasury.migrate(address(replacement));
    }

    function testMigrateBeforeRevokeReverts() public {
        _setTreasuryReplacement(address(replacement));

        vm.expectRevert(AgenticTreasury.TreasuryNotRevoked.selector);
        treasury.migrate(address(replacement));
    }

    function testMigrateRevokedWithoutReplacementReverts() public {
        _revokeTreasury();

        vm.expectRevert(
            abi.encodeWithSelector(AgenticTreasury.NotRegistryReplacement.selector, address(0), address(replacement))
        );
        treasury.migrate(address(replacement));
    }

    function testMigrateWrongRegistryReplacementReverts() public {
        _prepareMigration(address(replacement2));

        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticTreasury.NotRegistryReplacement.selector, address(replacement2), address(replacement)
            )
        );
        treasury.migrate(address(replacement));
    }

    function testMigrateZeroReplacementReverts() public {
        _prepareMigration(address(replacement));

        vm.expectRevert(Governance2Step.ZeroAddress.selector);
        treasury.migrate(address(0));
    }

    function testMigrateSelfReplacementReverts() public {
        _prepareMigration(address(treasury));

        vm.expectRevert(AgenticTreasury.ReplacementIsSelf.selector);
        treasury.migrate(address(treasury));
    }

    function testMigrateWrongCategoryReverts() public {
        _prepareMigration(address(replacement));
        venueRegistry.setFacilityForTest(address(replacement), FacilityCategory.POOL, TREASURY, true);

        vm.expectRevert(
            abi.encodeWithSelector(AgenticTreasury.ReplacementNotFeeRecipient.selector, address(replacement))
        );
        treasury.migrate(address(replacement));
    }

    function testMigrateInactiveReplacementReverts() public {
        _prepareMigration(address(replacement));
        venueRegistry.setFacilityForTest(address(replacement), FacilityCategory.FEE_RECIPIENT, TREASURY, false);

        vm.expectRevert(
            abi.encodeWithSelector(AgenticTreasury.ReplacementNotFeeRecipient.selector, address(replacement))
        );
        treasury.migrate(address(replacement));
    }

    function testMigrateSetsTargetAndEmits() public {
        _prepareMigration(address(replacement));

        vm.expectEmit(true, false, false, true, address(treasury));
        emit TreasuryMigrated(address(replacement));
        treasury.migrate(address(replacement));

        // The recorded target is now the one non-agent gated recipient.
        treasury.transferToken(address(gatedToken), address(replacement), 1e18);
        assertEq(gatedToken.balanceOf(address(replacement)), 1e18);
    }

    function testMigrateDoesNotMoveTokensOrNative() public {
        _fundNative();
        _prepareMigration(address(replacement));

        uint256 gatedBefore = gatedToken.balanceOf(address(treasury));
        uint256 publicBefore = publicToken.balanceOf(address(treasury));
        uint256 nativeBefore = address(treasury).balance;

        treasury.migrate(address(replacement));

        assertEq(gatedToken.balanceOf(address(treasury)), gatedBefore);
        assertEq(publicToken.balanceOf(address(treasury)), publicBefore);
        assertEq(address(treasury).balance, nativeBefore);
    }

    // ------------------------------------------------------- target exception

    function testTargetExceptionNotUsableBeforeMigrate() public {
        _prepareMigration(address(replacement));

        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticTreasury.GatedRecipientNotAgent.selector, address(gatedToken), address(replacement)
            )
        );
        treasury.transferToken(address(gatedToken), address(replacement), 1e18);
    }

    function testGatedTransferToTargetWorksOnlyAfterMigrate() public {
        _prepareMigration(address(replacement));

        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticTreasury.GatedRecipientNotAgent.selector, address(gatedToken), address(replacement)
            )
        );
        treasury.transferToken(address(gatedToken), address(replacement), 1e18);

        treasury.migrate(address(replacement));
        treasury.transferToken(address(gatedToken), address(replacement), 1e18);

        assertEq(gatedToken.balanceOf(address(replacement)), 1e18);
    }

    function testTargetExceptionRequiresActiveReplacement() public {
        _prepareMigration(address(replacement));
        treasury.migrate(address(replacement));
        venueRegistry.setRevokedForTest(address(replacement), true);
        policy.setPermissive(true);

        // Even a permissive/future token policy cannot make the treasury pay a
        // revoked migration target.
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticTreasury.GatedRecipientNotAgent.selector, address(gatedToken), address(replacement)
            )
        );
        treasury.transferToken(address(gatedToken), address(replacement), 1e18);
    }

    function testTargetExceptionRequiresGovernance() public {
        _prepareMigration(address(replacement));
        treasury.migrate(address(replacement));

        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonGov));
        treasury.transferToken(address(gatedToken), address(replacement), 1e18);
    }

    function testTargetExceptionRequiresLiveRevocation() public {
        _prepareMigration(address(replacement));
        treasury.migrate(address(replacement));

        venueRegistry.setRevokedForTest(address(treasury), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticTreasury.GatedRecipientNotAgent.selector, address(gatedToken), address(replacement)
            )
        );
        treasury.transferToken(address(gatedToken), address(replacement), 1e18);

        venueRegistry.setRevokedForTest(address(treasury), true);
        treasury.transferToken(address(gatedToken), address(replacement), 1e18);
        assertEq(gatedToken.balanceOf(address(replacement)), 1e18);
    }

    function testTargetExceptionRequiresLiveRegistryReplacement() public {
        _prepareMigration(address(replacement));
        treasury.migrate(address(replacement));
        venueRegistry.setReplacementForTest(address(treasury), address(replacement2));

        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticTreasury.GatedRecipientNotAgent.selector, address(gatedToken), address(replacement)
            )
        );
        treasury.transferToken(address(gatedToken), address(replacement), 1e18);

        treasury.migrate(address(replacement2));
        treasury.transferToken(address(gatedToken), address(replacement2), 1e18);
        assertEq(gatedToken.balanceOf(address(replacement2)), 1e18);

        // The old target stays rejected once the registry points elsewhere.
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticTreasury.GatedRecipientNotAgent.selector, address(gatedToken), address(replacement)
            )
        );
        treasury.transferToken(address(gatedToken), address(replacement), 1e18);
    }

    function testTargetExceptionNotUsedByDistribute() public {
        _prepareMigration(address(replacement));
        treasury.migrate(address(replacement));

        address[] memory recipients = new address[](1);
        recipients[0] = address(replacement);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;

        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticTreasury.GatedRecipientNotAgent.selector, address(gatedToken), address(replacement)
            )
        );
        treasury.distributeToken(address(gatedToken), recipients, amounts);
    }

    // ---------------------------------------------- public/native after migration

    function testPublicAndNativeRemainUnderGovernanceAfterMigrate() public {
        _fundNative();
        _prepareMigration(address(replacement));
        treasury.migrate(address(replacement));

        treasury.transferToken(address(publicToken), nonAgent, 5e18);
        treasury.transferNative(payable(nonAgent), 2e18);

        assertEq(publicToken.balanceOf(nonAgent), 5e18);
        assertEq(nonAgent.balance, 2e18);
    }

    // ------------------------------------------------- permissive policy defence

    /// @dev A policy that reports every address as a member cannot make `migrate`
    /// succeed: the treasury still requires revocation, the exact registry
    /// replacement, and an active FEE_RECIPIENT.
    function testPermissivePolicyCannotBypassMigratePrerequisites() public {
        policy.setPermissive(true);

        vm.expectRevert(AgenticTreasury.TreasuryNotRevoked.selector);
        treasury.migrate(address(replacement));

        _revokeTreasury();
        vm.expectRevert(
            abi.encodeWithSelector(AgenticTreasury.NotRegistryReplacement.selector, address(0), address(replacement))
        );
        treasury.migrate(address(replacement));

        _setTreasuryReplacement(address(replacement2));
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticTreasury.NotRegistryReplacement.selector, address(replacement2), address(replacement)
            )
        );
        treasury.migrate(address(replacement));

        _setTreasuryReplacement(address(replacement));
        venueRegistry.setFacilityForTest(address(replacement), FacilityCategory.POOL, TREASURY, true);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticTreasury.ReplacementNotFeeRecipient.selector, address(replacement))
        );
        treasury.migrate(address(replacement));

        venueRegistry.setFacilityForTest(address(replacement), FacilityCategory.FEE_RECIPIENT, TREASURY, true);
        treasury.migrate(address(replacement));
        assertEq(gatedToken.balanceOf(address(treasury)), INITIAL_BALANCE);
    }
}
