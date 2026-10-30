// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LAUNCH, VAULT} from "../../contracts/common/Types.sol";
import {AgenticFacilityBase} from "../../contracts/facility/AgenticFacilityBase.sol";
import {AgenticFacilityFactory} from "../../contracts/facility/AgenticFacilityFactory.sol";
import {AgenticEscrowFacility} from "../../contracts/facility/AgenticEscrowFacility.sol";
import {AgenticGameFacility} from "../../contracts/facility/AgenticGameFacility.sol";
import {AgenticLendingFacility} from "../../contracts/facility/AgenticLendingFacility.sol";
import {AgenticVaultFacility} from "../../contracts/facility/AgenticVaultFacility.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";

import {FacilityFixture} from "../helpers/FacilityFixture.sol";

contract FacilityFuzzTest is FacilityFixture {
    function setUp() public {
        _deployFacilities();
    }

    function testFuzzFactoryOwnerMayBeAnyNonZeroAddress(address owner_) public {
        vm.assume(owner_ != address(0));
        AgenticVaultFacility vault = _createVault(owner_);
        assertEq(vault.owner(), owner_);
    }

    function testFuzzFactoryRejectsArbitraryNonAgentBeneficiary(address beneficiary) public {
        vm.assume(beneficiary != address(0));
        vm.assume(!policy.isMember(beneficiary));
        vm.assume(!policy.isFacility(beneficiary));

        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.AgentRequired.selector, beneficiary));
        facilities.createFacility(LAUNCH, abi.encode(projectOwner, projectOwner, beneficiary));
    }

    function testFuzzFactoryRejectsUnsupportedKind(bytes32 kind) public {
        vm.assume(
            kind != VAULT && kind != LAUNCH && kind != keccak256("LOCKER") && kind != keccak256("GAME")
                && kind != keccak256("ESCROW") && kind != keccak256("LENDING")
        );
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.UnsupportedFacilityType.selector, kind));
        facilities.createFacility(kind, abi.encode(projectOwner));
    }

    function testFuzzVaultReleaseRejectsNonOwnerCaller(address caller) public {
        AgenticVaultFacility vault = _defaultVault();
        AgenticToken token = _fundVault(vault, 100 ether);
        vm.assume(caller != projectOwner);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, caller));
        vault.release(address(token), agent, 1 ether);
    }

    function testFuzzVaultReleaseRejectsArbitraryNonAgentRecipient(address recipient) public {
        AgenticVaultFacility vault = _defaultVault();
        AgenticToken token = _fundVault(vault, 100 ether);
        vm.assume(recipient != address(0));
        vm.assume(!policy.isMember(recipient));
        vm.assume(!policy.isFacility(recipient));

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.GatedRecipientNotAgent.selector, recipient));
        vault.release(address(token), recipient, 1 ether);
    }

    function testFuzzVaultReleaseAmount(uint256 amount) public {
        AgenticVaultFacility vault = _defaultVault();
        AgenticToken token = _fundVault(vault, 1_000 ether);
        amount = bound(amount, 0, 1_000 ether);

        vm.prank(projectOwner);
        vault.release(address(token), agent, amount);

        assertEq(token.balanceOf(agent), amount);
        assertEq(token.balanceOf(address(vault)), 1_000 ether - amount);
    }

    function testFuzzVaultReleaseRejectsArbitraryToken(address token_) public {
        AgenticVaultFacility vault = _defaultVault();
        AgenticToken gated = _fundVault(vault, 100 ether);
        vm.assume(token_ != address(0));
        vm.assume(token_ != address(gated));

        vm.prank(projectOwner);
        vm.expectRevert();
        vault.release(token_, agent, 1 ether);
    }

    function testFuzzMigrateRejectsWrongReplacement(address replacement) public {
        AgenticVaultFacility old = _createVault(projectOwner);
        AgenticVaultFacility expected = _createVault(projectOwner);
        _fundVault(old, 10 ether);
        _revoke(address(old));
        _setReplacement(address(old), address(expected));

        vm.assume(replacement != address(0));
        vm.assume(replacement != address(old));
        vm.assume(replacement != address(expected));

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticFacilityBase.NotRegistryReplacement.selector, address(expected), replacement)
        );
        old.migrate(replacement);
    }

    function testFuzzNoPublicRoleSetters(address caller) public {
        AgenticVaultFacility vault = _defaultVault();
        AgenticToken token = _fundVault(vault, 10 ether);
        vm.assume(caller != projectOwner);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, caller));
        vault.transferOwnership(caller);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, caller));
        vault.release(address(token), agent, 1 ether);
    }

    function testFuzzGameRejectsNonOperator(address caller) public {
        AgenticGameFacility game = _defaultGame();
        AgenticToken token = _fundGame(game, 10 ether);
        vm.assume(caller != projectOwner);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(AgenticGameFacility.NotOperator.selector, caller));
        game.consume(address(token), 1 ether);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(AgenticGameFacility.NotOperator.selector, caller));
        game.release(address(token), agent, 1 ether);
    }

    function testFuzzEscrowRejectsNonRole(address caller) public {
        AgenticEscrowFacility escrow = _defaultEscrow();
        AgenticToken token = _gatedToAgent(agent, 10 ether);
        vm.prank(agent);
        token.approve(address(escrow), type(uint256).max);
        vm.prank(agent);
        escrow.deposit(address(token), 5 ether);
        vm.assume(caller != agent && caller != projectOwner);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(AgenticEscrowFacility.NotBeneficiaryOrArbiter.selector, caller));
        escrow.release(address(token), agent, 1 ether);
    }

    function testFuzzLendingRejectsNonLender(address caller) public {
        AgenticLendingFacility lending = _defaultLending();
        AgenticToken token = _gatedToAgent(agent, 10 ether);
        vm.prank(agent);
        token.approve(address(lending), type(uint256).max);
        vm.prank(agent);
        lending.deposit(address(token), 5 ether);
        vm.assume(caller != agent);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(AgenticLendingFacility.NotLender.selector, caller));
        lending.withdraw(address(token), agent, 1 ether);
    }
}
