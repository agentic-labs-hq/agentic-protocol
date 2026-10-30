// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FacilityCategory, GAME, LAUNCH, TransferKind, VAULT} from "../../contracts/common/Types.sol";
import {AgenticPolicy} from "../../contracts/policy/AgenticPolicy.sol";
import {MockFacility} from "../mocks/MockFacility.sol";
import {MockVenueRegistry} from "../mocks/MockVenueRegistry.sol";
import {PolicyVenueFixture} from "../helpers/PolicyVenueFixture.sol";

contract AgenticPolicyTest is PolicyVenueFixture {
    // Matrix columns: 0 agent, 1 POOL, 2 LP_MANAGER, 3 FEE_RECIPIENT, 4 CUSTODY, 5 PURPOSE.
    function _expectedMatrix(uint8 fromIdx, uint8 toIdx) internal pure returns (bool) {
        if (fromIdx == 0) {
            // Agent row: Agent, POOL, PURPOSE.
            return toIdx == 0 || toIdx == 1 || toIdx == 5;
        }
        if (fromIdx == 1) {
            // POOL row: Agent, FEE_RECIPIENT. No LP_MANAGER: the NPM
            // never needs to receive gated tokens.
            return toIdx == 0 || toIdx == 3;
        }
        // LP_MANAGER/FEE_RECIPIENT/CUSTODY/PURPOSE rows: Agent only.
        return toIdx == 0;
    }

    function setUp() public {
        _deployPolicyVenue();
    }

    function _assertAllowed(address from, address to) internal view {
        (bool allowed, bytes32 reason) = _transfer(from, to);
        assertTrue(allowed);
        assertEq(reason, bytes32(0));
    }

    function _assertDenied(address from, address to) internal view {
        (bool allowed, bytes32 reason) = _transfer(from, to);
        assertFalse(allowed);
        assertTrue(reason != bytes32(0));
    }

    function _transferWithContext(address from, address to, bytes memory context)
        internal
        view
        returns (bool allowed, bytes32 reason)
    {
        return policy.canTransfer(address(0x1234), from, to, address(0x9999), context);
    }

    // ------------------------------------------------------------------ matrix

    function testFullCategoryMatrix() public view {
        address[6] memory froms =
            [agent, address(pool), address(lpManager), address(feeRecipient), address(vault), address(game)];
        address[6] memory tos =
            [agent2, address(pool), address(lpManager), address(feeRecipient), address(vault), address(game)];

        for (uint8 i = 0; i < 6; ++i) {
            for (uint8 j = 0; j < 6; ++j) {
                (bool allowed,) = _transfer(froms[i], tos[j]);
                assertEq(allowed, _expectedMatrix(i, j), "matrix cell mismatch");
            }
        }
    }

    function testAgentSelfTransferAllowed() public view {
        (bool allowed,) = _transfer(agent, agent);
        assertTrue(allowed);
    }

    function testFacilitySelfTransferDenied() public view {
        (bool allowed,) = _transfer(address(pool), address(pool));
        assertFalse(allowed);
        (allowed,) = _transfer(address(lpManager), address(lpManager));
        assertFalse(allowed);
        (allowed,) = _transfer(address(feeRecipient), address(feeRecipient));
        assertFalse(allowed);
        (allowed,) = _transfer(address(vault), address(vault));
        assertFalse(allowed);
        (allowed,) = _transfer(address(game), address(game));
        assertFalse(allowed);
    }

    function testAgentToCustodyDenied() public view {
        _assertDenied(agent, address(vault));
        _assertDenied(agent2, address(vault));
    }

    function testAgentToPurposeAllowed() public view {
        _assertAllowed(agent, address(game));
        _assertAllowed(agent2, address(game));
    }

    function testCustodyOnlyToAgent() public view {
        _assertAllowed(address(vault), agent2);
        _assertDenied(address(vault), address(pool));
        _assertDenied(address(vault), address(lpManager));
        _assertDenied(address(vault), address(feeRecipient));
        _assertDenied(address(vault), address(vault));
        _assertDenied(address(vault), address(game));
    }

    function testPurposeOnlyToAgent() public view {
        _assertAllowed(address(game), agent2);
        _assertDenied(address(game), address(pool));
        _assertDenied(address(game), address(lpManager));
        _assertDenied(address(game), address(feeRecipient));
        _assertDenied(address(game), address(vault));
        _assertDenied(address(game), address(pool));
    }

    function testPoolProtocolExceptions() public view {
        _assertAllowed(address(pool), agent2);
        _assertDenied(address(pool), address(lpManager));
        _assertAllowed(address(pool), address(feeRecipient));
        _assertDenied(address(pool), address(pool));
        _assertDenied(address(pool), address(vault));
        _assertDenied(address(pool), address(game));
    }

    function testNoUserFacilityToFacility() public view {
        _assertDenied(address(vault), address(game));
        _assertDenied(address(game), address(vault));
        _assertDenied(address(lpManager), address(feeRecipient));
        _assertDenied(address(feeRecipient), address(lpManager));
        _assertDenied(address(vault), address(lpManager));
        _assertDenied(address(game), address(pool));
    }

    function testNonAgentEOADeniedBothDirections() public view {
        _assertDenied(nonAgent, agent2);
        _assertDenied(agent, nonAgent);
        _assertDenied(nonAgent, address(pool));
        _assertDenied(address(pool), nonAgent);
        _assertDenied(nonAgent, address(vault));
        _assertDenied(address(vault), nonAgent);
        _assertDenied(nonAgent, nonAgent);
    }

    // -------------------------------------------------------------- mint / burn

    function testMintToEligibleRecipients() public view {
        _assertAllowed(address(0), agent2);
        _assertAllowed(address(0), address(pool));
        _assertAllowed(address(0), address(lpManager));
        _assertAllowed(address(0), address(feeRecipient));
        _assertAllowed(address(0), address(vault));
        _assertAllowed(address(0), address(game));
    }

    function testMintToNonAgentDenied() public view {
        _assertDenied(address(0), nonAgent);
    }

    function testMintToZeroDenied() public view {
        _assertDenied(address(0), address(0));
    }

    function testMintToRevokedFacilityDenied() public {
        venue.revokeFacility(address(vault));
        _assertDenied(address(0), address(vault));
    }

    function testBurnAlwaysDenied() public view {
        _assertDenied(agent, address(0));
        _assertDenied(address(pool), address(0));
        _assertDenied(address(vault), address(0));
        _assertDenied(address(game), address(0));
        _assertDenied(nonAgent, address(0));
    }

    // ------------------------------------------------------------------ context

    function testValidTransferContext() public view {
        (bool allowed,) = _transferWithContext(agent, agent2, abi.encode(TransferKind.TRANSFER));
        assertTrue(allowed);
        assertEq(uint256(TransferKind.TRANSFER), 0);
    }

    function testEmptyContextDenied() public view {
        (bool allowed, bytes32 reason) = _transferWithContext(agent, agent2, "");
        assertFalse(allowed);
        assertTrue(reason != bytes32(0));
    }

    function testShortContextDenied() public view {
        bytes memory short = new bytes(31);
        (bool allowed,) = _transferWithContext(agent, agent2, short);
        assertFalse(allowed);
    }

    function testLongContextDenied() public view {
        bytes memory long = new bytes(33);
        (bool allowed,) = _transferWithContext(agent, agent2, long);
        assertFalse(allowed);
    }

    function testNonTransferKindDenied() public view {
        (bool allowed,) = _transferWithContext(agent, agent2, abi.encode(uint256(1)));
        assertFalse(allowed);
        (allowed,) = _transferWithContext(agent, agent2, abi.encode(type(uint256).max));
        assertFalse(allowed);
        (allowed,) = _transferWithContext(agent, agent2, abi.encode(uint8(2)));
        assertFalse(allowed);
    }

    // -------------------------------------------------------------- identity

    function testIdentityViews() public view {
        assertEq(policy.identityRegistry(), address(identityRegistry));
        assertEq(policy.facilityRegistry(), address(venue));
        assertEq(policy.AGENT_ID_KIND(), keccak256("AGENT_ID"));
        assertEq(policy.AGENT_ID_KIND(), identityAdapter.kind());
    }

    function testIsMember() public view {
        assertTrue(policy.isMember(agent));
        assertTrue(policy.isMember(agent2));
        assertFalse(policy.isMember(nonAgent));
        assertFalse(policy.isMember(address(0)));
        assertFalse(policy.isMember(address(vault)));
    }

    function testNoAdapterFailsClosed() public {
        identityRegistry.setAdapter(keccak256("AGENT_ID"), address(0));
        assertFalse(policy.isMember(agent));
        _assertDenied(agent, agent2);
        _assertDenied(address(0), agent2);
        _assertDenied(address(0), agent);
        // Facilities stay eligible on their own.
        assertTrue(policy.isEligible(address(vault)));
        _assertAllowed(address(0), address(vault));
        // A facility cannot send to an address whose agent status cannot be read.
        _assertDenied(address(pool), agent2);
    }

    function testFacilityAndCategoryViews() public view {
        assertTrue(policy.isFacility(address(pool)));
        assertTrue(policy.isFacility(address(lpManager)));
        assertTrue(policy.isFacility(address(feeRecipient)));
        assertTrue(policy.isFacility(address(vault)));
        assertTrue(policy.isFacility(address(game)));
        assertFalse(policy.isFacility(nonAgent));
        assertFalse(policy.isFacility(address(0)));

        assertEq(uint256(policy.categoryOf(address(pool))), uint256(FacilityCategory.POOL));
        assertEq(uint256(policy.categoryOf(address(lpManager))), uint256(FacilityCategory.LP_MANAGER));
        assertEq(uint256(policy.categoryOf(address(feeRecipient))), uint256(FacilityCategory.FEE_RECIPIENT));
        assertEq(uint256(policy.categoryOf(address(vault))), uint256(FacilityCategory.CUSTODY));
        assertEq(uint256(policy.categoryOf(address(game))), uint256(FacilityCategory.PURPOSE));
        assertEq(uint256(policy.categoryOf(nonAgent)), uint256(FacilityCategory.NONE));

        assertTrue(policy.isEligible(agent));
        assertTrue(policy.isEligible(address(vault)));
        assertFalse(policy.isEligible(nonAgent));
        assertFalse(policy.isEligible(address(0)));

        assertFalse(policy.isRevokedFacility(address(vault)));
        assertEq(policy.replacementOf(address(vault)), address(0));
    }

    function testRevokedFacilityWithAgentIdCannotReceiveGated() public {
        identityAdapter.setHasIdentity(address(vault), true);
        identityAdapter.setHasIdentity(address(pool), true);
        venue.revokeFacility(address(vault));

        // Category (revoked) takes precedence over the Agent ID on every inbound
        // path: agent, active facility, and the frozen facility itself.
        _assertDenied(agent, address(vault));
        _assertDenied(address(pool), address(vault));
        _assertDenied(address(vault), address(vault));
        _assertDenied(address(0), address(vault));
        assertFalse(policy.isEligible(address(vault)));
    }

    function testFacilityCategoryTakesPrecedenceOverMembership() public {
        identityAdapter.setHasIdentity(address(vault), true);
        identityAdapter.setHasIdentity(address(pool), true);
        assertTrue(policy.isMember(address(vault)));
        assertTrue(policy.isMember(address(pool)));

        // A CUSTODY holding an Agent ID still cannot use the Agent row/column.
        _assertDenied(agent, address(vault));
        _assertDenied(address(vault), address(pool));
        _assertDenied(address(vault), address(lpManager));
        _assertAllowed(address(vault), agent2);

        // A POOL holding an Agent ID still cannot be an Agent -> POOL source row.
        _assertDenied(address(pool), address(pool));
        _assertDenied(address(pool), address(vault));
    }

    // -------------------------------------------------- revoke / replacement

    function testRevokedFacilityOnlyToActiveSameSubtypeReplacement() public {
        MockFacility second = _createFacility(VAULT, projectOwner);
        MockFacility third = _createFacility(VAULT, projectOwner);

        venue.revokeFacility(address(vault));
        vm.prank(projectOwner);
        venue.setReplacement(address(vault), address(second));

        assertTrue(policy.isRevokedFacility(address(vault)));
        assertEq(policy.replacementOf(address(vault)), address(second));
        assertEq(uint256(policy.categoryOf(address(vault))), uint256(FacilityCategory.CUSTODY));

        _assertAllowed(address(vault), address(second));
        _assertDenied(address(vault), agent);
        _assertDenied(address(vault), address(pool));
        _assertDenied(address(vault), address(game));
        _assertDenied(address(vault), address(third));
        _assertDenied(agent, address(vault));
    }

    function testRevokedWithoutReplacementIsFrozen() public {
        MockFacility second = _createFacility(GAME, projectOwner);
        venue.revokeFacility(address(game));

        assertEq(policy.replacementOf(address(game)), address(0));
        _assertDenied(address(game), agent);
        _assertDenied(address(game), address(second));
        _assertDenied(agent, address(game));
    }

    function testRevokedReplacementThatIsRevokedLaterDenied() public {
        MockFacility second = _createFacility(VAULT, projectOwner);
        venue.revokeFacility(address(vault));
        vm.prank(projectOwner);
        venue.setReplacement(address(vault), address(second));

        venue.revokeFacility(address(second));
        _assertDenied(address(vault), address(second));
    }

    function testRevokedPurposeReplacement() public {
        MockFacility second = _createFacility(GAME, projectOwner);
        venue.revokeFacility(address(game));
        vm.prank(projectOwner);
        venue.setReplacement(address(game), address(second));

        _assertAllowed(address(game), address(second));
        _assertDenied(address(game), agent);
    }

    function testConstructorRejectsZeroRegistries() public {
        vm.expectRevert(AgenticPolicy.ZeroRegistry.selector);
        new AgenticPolicy(address(0), address(venue));

        vm.expectRevert(AgenticPolicy.ZeroRegistry.selector);
        new AgenticPolicy(address(identityRegistry), address(0));
    }

    // --------------------------------------- policy-level registry defense

    /// @dev The real registry enforces these conditions in `setReplacement`.
    /// This deliberately permissive mock proves the policy re-checks them too,
    /// so a buggy/malicious registry cannot open a revoked-facility bypass.
    function testPolicyRechecksRevokedReplacement() public {
        MockVenueRegistry loose = new MockVenueRegistry();
        AgenticPolicy loosePolicy = new AgenticPolicy(address(identityRegistry), address(loose));

        address revokedFacility = address(0x1111);
        address candidate = address(0x2222);
        bytes memory context = abi.encode(TransferKind.TRANSFER);

        loose.setFacilityForTest(revokedFacility, FacilityCategory.CUSTODY, VAULT, false);
        loose.setRevokedForTest(revokedFacility, true);

        (bool allowed,) = loosePolicy.canTransfer(address(0), revokedFacility, candidate, address(0), context);
        assertFalse(allowed); // replacementOf == 0

        loose.setReplacementForTest(revokedFacility, candidate);

        loose.setFacilityForTest(candidate, FacilityCategory.CUSTODY, LAUNCH, true);
        (allowed,) = loosePolicy.canTransfer(address(0), revokedFacility, candidate, address(0), context);
        assertFalse(allowed); // wrong subtype

        loose.setFacilityForTest(candidate, FacilityCategory.PURPOSE, VAULT, true);
        (allowed,) = loosePolicy.canTransfer(address(0), revokedFacility, candidate, address(0), context);
        assertFalse(allowed); // wrong category

        loose.setFacilityForTest(candidate, FacilityCategory.CUSTODY, VAULT, true);
        (allowed,) = loosePolicy.canTransfer(address(0), revokedFacility, candidate, address(0), context);
        assertTrue(allowed); // same category + subtype, active

        loose.setFacilityForTest(candidate, FacilityCategory.CUSTODY, VAULT, false);
        (allowed,) = loosePolicy.canTransfer(address(0), revokedFacility, candidate, address(0), context);
        assertFalse(allowed); // inactive replacement
    }
}
