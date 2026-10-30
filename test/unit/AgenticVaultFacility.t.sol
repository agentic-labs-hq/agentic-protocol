// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgenticFacilityBase} from "../../contracts/facility/AgenticFacilityBase.sol";
import {AgenticVaultFacility} from "../../contracts/facility/AgenticVaultFacility.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";

import {MockTransferPolicy} from "../mocks/MockTransferPolicy.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {FacilityFixture} from "../helpers/FacilityFixture.sol";

contract AgenticVaultFacilityTest is FacilityFixture {
    AgenticVaultFacility internal vaultFacility;
    AgenticToken internal token;

    function setUp() public {
        _deployFacilities();
        vaultFacility = _defaultVault();
        token = _fundVault(vaultFacility, 1_000 ether);
    }

    function testVaultReleaseOwnerToAgent() public {
        vm.prank(projectOwner);
        vaultFacility.release(address(token), agent, 400 ether);

        assertEq(token.balanceOf(agent), 400 ether);
        assertEq(token.balanceOf(address(vaultFacility)), 600 ether);
    }

    function testVaultReleaseOnlyOwner() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, agent));
        vaultFacility.release(address(token), agent, 1 ether);

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, nonAgent));
        vaultFacility.release(address(token), agent, 1 ether);

        vm.prank(address(vaultFacility));
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, address(vaultFacility)));
        vaultFacility.release(address(token), agent, 1 ether);
    }

    function testVaultReleaseRejectsNonAgentRecipient() public {
        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.GatedRecipientNotAgent.selector, nonAgent));
        vaultFacility.release(address(token), nonAgent, 1 ether);
    }

    function testVaultReleaseRejectsFacilityRecipient() public {
        AgenticVaultFacility other = _createVault(projectOwner);
        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticFacilityBase.FacilityRecipientNotAllowed.selector, address(other))
        );
        vaultFacility.release(address(token), address(other), 1 ether);
    }

    function testVaultRejectsRevokedFacilityWithAgentIdAsRecipient() public {
        AgenticVaultFacility revoked = _createVault(projectOwner);
        // A facility that also holds an Agent ID must still be classified as a
        // facility, including after revoke (category persists).
        identityAdapter.setHasIdentity(address(revoked), true);
        _revoke(address(revoked));

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticFacilityBase.FacilityRecipientNotAllowed.selector, address(revoked))
        );
        vaultFacility.release(address(token), address(revoked), 1 ether);
    }

    function testVaultReleaseRejectsZeroTokenAndRecipient() public {
        vm.prank(projectOwner);
        vm.expectRevert(AgenticFacilityBase.ZeroToken.selector);
        vaultFacility.release(address(0), agent, 1 ether);

        vm.prank(projectOwner);
        vm.expectRevert(AgenticFacilityBase.ZeroRecipient.selector);
        vaultFacility.release(address(token), address(0), 1 ether);
    }

    function testVaultReleaseRejectsInsufficientBalance() public {
        vm.prank(projectOwner);
        vm.expectRevert();
        vaultFacility.release(address(token), agent, 1_001 ether);
    }

    function testVaultMultiTokenRelease() public {
        AgenticToken second = _fundVault(vaultFacility, 500 ether);

        vm.startPrank(projectOwner);
        vaultFacility.release(address(token), agent, 100 ether);
        vaultFacility.release(address(second), agent2, 200 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(agent), 100 ether);
        assertEq(second.balanceOf(agent2), 200 ether);
        assertEq(token.balanceOf(address(vaultFacility)), 900 ether);
        assertEq(second.balanceOf(address(vaultFacility)), 300 ether);
    }

    function testVaultReleaseNativeOwnerToAnyone() public {
        vm.deal(address(vaultFacility), 2 ether);

        vm.prank(projectOwner);
        vaultFacility.releaseNative(payable(nonAgent), 1 ether);

        assertEq(nonAgent.balance, 1 ether);
        assertEq(address(vaultFacility).balance, 1 ether);
    }

    function testVaultReleaseNativeOnlyOwner() public {
        vm.deal(address(vaultFacility), 1 ether);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, agent));
        vaultFacility.releaseNative(payable(agent), 1 ether);
    }

    function testVaultReleaseNativeRejectsZeroRecipient() public {
        vm.deal(address(vaultFacility), 1 ether);
        vm.prank(projectOwner);
        vm.expectRevert(AgenticFacilityBase.ZeroRecipient.selector);
        vaultFacility.releaseNative(payable(address(0)), 1 ether);
    }

    function testVaultAcceptsNativeDirectly() public {
        vm.deal(agent, 1 ether);
        vm.prank(agent);
        (bool sent,) = address(vaultFacility).call{value: 1 ether}("");
        assertTrue(sent);
        assertEq(address(vaultFacility).balance, 1 ether);
    }

    function testVaultTwoStepOwnership() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, agent));
        vaultFacility.transferOwnership(agent);

        vm.prank(projectOwner);
        vaultFacility.transferOwnership(agent);
        assertEq(vaultFacility.pendingOwner(), agent);
        assertEq(vaultFacility.owner(), projectOwner);

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotPendingOwner.selector, nonAgent));
        vaultFacility.acceptOwnership();

        vm.prank(agent);
        vaultFacility.acceptOwnership();
        assertEq(vaultFacility.owner(), agent);
        assertEq(vaultFacility.pendingOwner(), address(0));

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, projectOwner));
        vaultFacility.release(address(token), agent2, 1 ether);

        vm.prank(agent);
        vaultFacility.release(address(token), agent2, 1 ether);
        assertEq(token.balanceOf(agent2), 1 ether);
    }

    function testVaultTransferOwnershipRejectsZero() public {
        vm.prank(projectOwner);
        vm.expectRevert(AgenticFacilityBase.ZeroAddress.selector);
        vaultFacility.transferOwnership(address(0));
    }

    function testVaultPermissiveTokenPolicyCannotBypassBaseGuard() public {
        MockTransferPolicy permissive = new MockTransferPolicy();
        permissive.setPermissive(true);
        policyRegistry.addPolicy(address(permissive), 2);
        AgenticToken permissiveToken = _gatedToWithPolicy(address(vaultFacility), address(permissive), 100 ether);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.GatedRecipientNotAgent.selector, nonAgent));
        vaultFacility.release(address(permissiveToken), nonAgent, 1 ether);

        vm.prank(projectOwner);
        vaultFacility.release(address(permissiveToken), agent, 1 ether);
        assertEq(permissiveToken.balanceOf(agent), 1 ether);
    }

    function testVaultPublicERC20OwnerCanReleaseToAnyNonZero() public {
        MockToken publicToken = _publicTokenTo(address(vaultFacility), 100 ether);

        vm.prank(projectOwner);
        vaultFacility.release(address(publicToken), projectOwner, 40 ether);
        assertEq(publicToken.balanceOf(projectOwner), 40 ether);

        AgenticVaultFacility other = _createVault(projectOwner);
        vm.prank(projectOwner);
        vaultFacility.release(address(publicToken), address(other), 10 ether);
        assertEq(publicToken.balanceOf(address(other)), 10 ether);

        vm.prank(projectOwner);
        vaultFacility.release(address(publicToken), nonAgent, 10 ether);
        assertEq(publicToken.balanceOf(nonAgent), 10 ether);
    }

    function testVaultPublicERC20NonOwnerReverts() public {
        MockToken publicToken = _publicTokenTo(address(vaultFacility), 100 ether);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, agent));
        vaultFacility.release(address(publicToken), nonAgent, 1 ether);
    }

    function testVaultGatedNonAgentStillRevertsAfterPublicPathAdded() public {
        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.GatedRecipientNotAgent.selector, nonAgent));
        vaultFacility.release(address(token), nonAgent, 1 ether);
    }
}
