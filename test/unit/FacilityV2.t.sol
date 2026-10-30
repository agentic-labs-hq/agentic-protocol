// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ESCROW, FacilityCategory, GAME, LAUNCH, LENDING, LOCKER, VAULT} from "../../contracts/common/Types.sol";
import {AgenticEscrowFacilityV2} from "../../contracts/facility/AgenticEscrowFacilityV2.sol";
import {AgenticEscrowFacility} from "../../contracts/facility/AgenticEscrowFacility.sol";
import {AgenticFacilityFactoryV2} from "../../contracts/facility/AgenticFacilityFactoryV2.sol";
import {
    AgenticFacilityFactoryV2,
    AgenticEscrowV2TemplateDeployer
} from "../../contracts/facility/AgenticFacilityFactoryV2.sol";
import {AgenticFacilityBase} from "../../contracts/facility/AgenticFacilityBase.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";

import {FacilityFixture} from "../helpers/FacilityFixture.sol";

contract FacilityV2Test is FacilityFixture {
    AgenticFacilityFactoryV2 internal facilitiesV2;

    function setUp() public {
        _deployFacilities();
        AgenticFacilityFactoryV2.TemplateDeployers memory deployers = AgenticFacilityFactoryV2.TemplateDeployers({
            vault: facilities.vaultDeployer(),
            launch: facilities.launchDeployer(),
            locker: facilities.lockerDeployer(),
            game: facilities.gameDeployer(),
            escrow: address(new AgenticEscrowV2TemplateDeployer())
        });
        facilitiesV2 = new AgenticFacilityFactoryV2(address(policy), address(venue), address(assetRegistry), deployers);
        venue.setRegistrar(address(facilitiesV2), FacilityCategory.CUSTODY, true);
        venue.setRegistrar(address(facilitiesV2), FacilityCategory.PURPOSE, true);
    }

    function _createEscrowV2(address owner_, address arbiter_, address beneficiary_, address depositor_)
        internal
        returns (AgenticEscrowFacilityV2)
    {
        return AgenticEscrowFacilityV2(
            facilitiesV2.createFacility(ESCROW, abi.encode(owner_, arbiter_, beneficiary_, depositor_))
        );
    }

    function testV2SupportsFiveKindsAndRejectsLending() public view {
        assertTrue(facilitiesV2.isSupportedType(VAULT));
        assertTrue(facilitiesV2.isSupportedType(LAUNCH));
        assertTrue(facilitiesV2.isSupportedType(LOCKER));
        assertTrue(facilitiesV2.isSupportedType(GAME));
        assertTrue(facilitiesV2.isSupportedType(ESCROW));
        assertFalse(facilitiesV2.isSupportedType(LENDING));
        assertEq(facilitiesV2.codehashOf(LENDING), bytes32(0));
    }

    function testV2CreatesFacilitiesWithRegistration() public {
        AgenticEscrowFacilityV2 escrow = _createEscrowV2(projectOwner, projectOwner, agent, agent);
        assertEq(escrow.factory(), address(facilitiesV2));
        assertEq(escrow.facilityType(), ESCROW);
        assertTrue(venue.isFacilityOfCategory(address(escrow), FacilityCategory.PURPOSE));
        assertEq(address(escrow).codehash, facilitiesV2.codehashOf(ESCROW));
    }

    function testV2CreatesAllFiveKinds() public {
        address vault = facilitiesV2.createFacility(VAULT, abi.encode(projectOwner));
        address launch = facilitiesV2.createFacility(LAUNCH, abi.encode(projectOwner, projectOwner, agent));
        address locker = facilitiesV2.createFacility(LOCKER, abi.encode(projectOwner, agent, DEFAULT_UNLOCK_TIME));
        address game = facilitiesV2.createFacility(GAME, abi.encode(projectOwner, projectOwner));
        address escrow = facilitiesV2.createFacility(ESCROW, abi.encode(projectOwner, projectOwner, agent, agent));

        assertTrue(venue.isFacility(vault));
        assertTrue(venue.isFacility(launch));
        assertTrue(venue.isFacility(locker));
        assertTrue(venue.isFacility(game));
        assertTrue(venue.isFacility(escrow));
        assertEq(address(vault).codehash, facilitiesV2.codehashOf(VAULT));
        assertEq(address(launch).codehash, facilitiesV2.codehashOf(LAUNCH));
        assertEq(address(locker).codehash, facilitiesV2.codehashOf(LOCKER));
        assertEq(address(game).codehash, facilitiesV2.codehashOf(GAME));
        assertEq(address(escrow).codehash, facilitiesV2.codehashOf(ESCROW));
    }

    function testEscrowV2PartialReleaseThenRemainder() public {
        AgenticEscrowFacilityV2 escrow = _createEscrowV2(projectOwner, projectOwner, agent, agent);
        AgenticToken token = _gatedToAgent(agent, 100 ether);
        vm.prank(agent);
        token.approve(address(escrow), type(uint256).max);
        vm.prank(agent);
        escrow.deposit(address(token), 100 ether);

        vm.prank(agent);
        escrow.release(address(token), agent2, 1 ether);
        assertEq(token.balanceOf(agent2), 1 ether);
        assertEq(token.balanceOf(address(escrow)), 99 ether);

        vm.prank(agent);
        escrow.release(address(token), agent2, 99 ether);
        assertEq(token.balanceOf(agent2), 100 ether);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function testEscrowV2PartialRefundThenRemainder() public {
        AgenticEscrowFacilityV2 escrow = _createEscrowV2(projectOwner, projectOwner, agent, agent);
        AgenticToken token = _gatedToAgent(agent, 100 ether);
        vm.prank(agent);
        token.approve(address(escrow), type(uint256).max);
        vm.prank(agent);
        escrow.deposit(address(token), 100 ether);

        vm.prank(agent);
        escrow.refund(address(token), agent, 40 ether);
        vm.prank(projectOwner);
        escrow.refund(address(token), agent2, 60 ether);
        assertEq(token.balanceOf(agent), 40 ether);
        assertEq(token.balanceOf(agent2), 60 ether);
    }

    function testEscrowV2CannotRedepositAfterFullSettlement() public {
        AgenticEscrowFacilityV2 escrow = _createEscrowV2(projectOwner, projectOwner, agent, agent);
        AgenticToken token = _gatedToAgent(agent, 2 ether);
        vm.prank(agent);
        token.approve(address(escrow), type(uint256).max);
        vm.prank(agent);
        escrow.deposit(address(token), 1 ether);
        vm.prank(agent);
        escrow.release(address(token), agent2, 1 ether);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticEscrowFacilityV2.EscrowAlreadySettled.selector, address(token)));
        escrow.deposit(address(token), 1 ether);
    }

    function testEscrowV2SettlementModeCannotFlip() public {
        AgenticEscrowFacilityV2 escrow = _createEscrowV2(projectOwner, projectOwner, agent, agent);
        AgenticToken token = _gatedToAgent(agent, 100 ether);
        vm.prank(agent);
        token.approve(address(escrow), type(uint256).max);
        vm.prank(agent);
        escrow.deposit(address(token), 100 ether);

        vm.prank(agent);
        escrow.release(address(token), agent2, 1 ether);

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticEscrowFacilityV2.SettlementModeLocked.selector,
                address(token),
                AgenticEscrowFacilityV2.SettlementMode.RELEASE
            )
        );
        escrow.refund(address(token), agent2, 1 ether);
    }

    function testEscrowV2RejectsZeroAndOverBalance() public {
        AgenticEscrowFacilityV2 escrow = _createEscrowV2(projectOwner, projectOwner, agent, agent);
        AgenticToken token = _gatedToAgent(agent, 10 ether);
        vm.prank(agent);
        token.approve(address(escrow), type(uint256).max);
        vm.prank(agent);
        escrow.deposit(address(token), 10 ether);

        vm.prank(agent);
        vm.expectRevert(AgenticEscrowFacilityV2.ZeroAmount.selector);
        escrow.release(address(token), agent2, 0);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticEscrowFacilityV2.InsufficientBalance.selector, address(token), 11 ether, 10 ether
            )
        );
        escrow.release(address(token), agent2, 11 ether);
    }

    function testV2FactoryRequiresLockerBeneficiary() public {
        vm.expectRevert(AgenticFacilityFactoryV2.LockerBeneficiaryRequired.selector);
        facilitiesV2.createFacility(LOCKER, abi.encode(projectOwner, address(0), DEFAULT_UNLOCK_TIME));
    }

    function testV2FactoryRequiresEscrowBeneficiaryAndDepositor() public {
        vm.expectRevert(AgenticFacilityFactoryV2.EscrowRolesRequired.selector);
        facilitiesV2.createFacility(ESCROW, abi.encode(projectOwner, projectOwner, address(0), agent));

        vm.expectRevert(AgenticFacilityFactoryV2.EscrowRolesRequired.selector);
        facilitiesV2.createFacility(ESCROW, abi.encode(projectOwner, projectOwner, agent, address(0)));
    }

    function testEscrowV2DustDepositCannotBecomeVictimDepositor() public {
        AgenticEscrowFacilityV2 escrow = _createEscrowV2(projectOwner, projectOwner, agent, agent);
        AgenticToken victim = AgenticToken(_createTokenFor(agent, address(escrow), 100 ether));
        AgenticToken dust = _gatedToAgent(agent2, 1);

        vm.prank(agent2);
        dust.approve(address(escrow), type(uint256).max);
        vm.prank(agent2);
        vm.expectRevert(abi.encodeWithSelector(AgenticEscrowFacilityV2.NotDepositor.selector, agent2));
        escrow.deposit(address(dust), 1);

        vm.prank(agent2);
        vm.expectRevert(abi.encodeWithSelector(AgenticEscrowFacilityV2.NotDepositorOrArbiter.selector, agent2));
        escrow.refund(address(victim), agent2, 100 ether);
    }

    function testEscrowV2InitialMintIsReleasable() public {
        AgenticEscrowFacilityV2 escrow = _createEscrowV2(projectOwner, projectOwner, agent, agent);
        AgenticToken token = AgenticToken(_createTokenFor(agent, address(escrow), 100 ether));

        vm.prank(agent);
        escrow.release(address(token), agent2, 100 ether);
        assertEq(token.balanceOf(agent2), 100 ether);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function testEscrowV2DirectTransferIsReleasable() public {
        AgenticEscrowFacilityV2 escrow = _createEscrowV2(projectOwner, projectOwner, agent, agent);
        AgenticToken token = _gatedToAgent(agent, 100 ether);

        vm.prank(agent);
        token.transfer(address(escrow), 100 ether);

        vm.prank(agent);
        escrow.release(address(token), agent2, 100 ether);
        assertEq(token.balanceOf(agent2), 100 ether);
    }

    function testEscrowV1CanMigrateIntoV2AndExit() public {
        AgenticEscrowFacilityV2 replacement = _createEscrowV2(projectOwner, projectOwner, agent, agent);
        AgenticEscrowFacility oldEscrow = _defaultEscrow();
        AgenticToken token = _gatedToAgent(agent, 100 ether);
        vm.prank(agent);
        token.approve(address(oldEscrow), type(uint256).max);
        vm.prank(agent);
        oldEscrow.deposit(address(token), 100 ether);

        _revoke(address(oldEscrow));
        _setReplacement(address(oldEscrow), address(replacement));
        vm.prank(projectOwner);
        oldEscrow.migrate(address(replacement));

        vm.prank(agent);
        oldEscrow.release(address(token), address(replacement), 100 ether);
        assertEq(token.balanceOf(address(replacement)), 100 ether);

        vm.prank(agent);
        replacement.release(address(token), agent2, 100 ether);
        assertEq(token.balanceOf(agent2), 100 ether);
    }

    function testEscrowV2MigrationTargetRemainderIsReleasable() public {
        AgenticEscrowFacilityV2 oldEscrow = _createEscrowV2(projectOwner, projectOwner, agent, agent);
        AgenticEscrowFacilityV2 replacement = _createEscrowV2(projectOwner, projectOwner, agent2, agent);
        AgenticToken token = _gatedToAgent(agent, 100 ether);
        vm.prank(agent);
        token.approve(address(oldEscrow), type(uint256).max);
        vm.prank(agent);
        oldEscrow.deposit(address(token), 100 ether);

        _revoke(address(oldEscrow));
        _setReplacement(address(oldEscrow), address(replacement));
        vm.prank(projectOwner);
        oldEscrow.migrate(address(replacement));

        vm.prank(agent);
        oldEscrow.release(address(token), address(replacement), 100 ether);
        assertEq(token.balanceOf(address(replacement)), 100 ether);
        assertEq(replacement.hasDeposit(), false);

        vm.prank(agent2);
        replacement.release(address(token), agent2, 100 ether);
        assertEq(token.balanceOf(agent2), 100 ether);
    }

    function testEscrowV2BeneficiaryFreezesAfterDeposit() public {
        AgenticEscrowFacilityV2 escrow = _createEscrowV2(projectOwner, projectOwner, agent, agent);
        AgenticToken token = _gatedToAgent(agent, 1 ether);
        vm.prank(agent);
        token.approve(address(escrow), type(uint256).max);
        vm.prank(agent);
        escrow.deposit(address(token), 1 ether);

        vm.prank(projectOwner);
        vm.expectRevert(AgenticEscrowFacilityV2.BeneficiaryAfterDeposit.selector);
        escrow.setBeneficiary(agent2);
    }

    function testEscrowV2RolesAreEnforced() public {
        AgenticEscrowFacilityV2 escrow = _createEscrowV2(projectOwner, projectOwner, agent, agent);
        AgenticToken token = _gatedToAgent(agent, 1 ether);
        vm.prank(agent);
        token.approve(address(escrow), type(uint256).max);
        vm.prank(agent);
        escrow.deposit(address(token), 1 ether);

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticEscrowFacilityV2.NotBeneficiaryOrArbiter.selector, nonAgent));
        escrow.release(address(token), agent2, 1 ether);

        vm.prank(agent2);
        vm.expectRevert(abi.encodeWithSelector(AgenticEscrowFacilityV2.NotDepositorOrArbiter.selector, agent2));
        escrow.refund(address(token), agent2, 1 ether);
    }

    function testOldFactoryCanBeDisabledWhileV2Creates() public {
        venue.setRegistrar(address(facilities), FacilityCategory.CUSTODY, false);
        venue.setRegistrar(address(facilities), FacilityCategory.PURPOSE, false);

        assertFalse(venue.isRegistrarFor(address(facilities), FacilityCategory.CUSTODY));
        assertFalse(venue.isRegistrarFor(address(facilities), FacilityCategory.PURPOSE));
        assertTrue(venue.isRegistrarFor(address(facilitiesV2), FacilityCategory.CUSTODY));
        assertTrue(venue.isRegistrarFor(address(facilitiesV2), FacilityCategory.PURPOSE));

        vm.expectRevert();
        facilities.createFacility(VAULT, abi.encode(projectOwner));

        vm.expectRevert();
        facilities.createFacility(LENDING, abi.encode(projectOwner, projectOwner, projectOwner, agent, agent));

        AgenticEscrowFacilityV2 escrow = _createEscrowV2(projectOwner, projectOwner, agent, agent);
        assertTrue(venue.isFacility(address(escrow)));
    }

    function testEscrowV2UnsupportedKindsStillRevert() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactoryV2.UnsupportedFacilityType.selector, LENDING));
        facilitiesV2.createFacility(LENDING, abi.encode(projectOwner, projectOwner, projectOwner, agent, agent));
    }
}
