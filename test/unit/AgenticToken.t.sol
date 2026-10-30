// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {AgenticPolicy} from "../../contracts/policy/AgenticPolicy.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";
import {AssetType, FacilityCategory, TransferKind} from "../../contracts/common/Types.sol";

import {MockTransferPolicy} from "../mocks/MockTransferPolicy.sol";
import {TokenAssetFixture} from "../helpers/TokenAssetFixture.sol";

contract AgenticTokenTest is TokenAssetFixture {
    uint256 internal constant INITIAL = 1_000 ether;

    AgenticToken internal token;

    function setUp() public {
        _deployTokenAsset();
        token = _createRegisteredToken();
    }

    // ---------------------------------------------------------------------
    // Construction and immutable stamps
    // ---------------------------------------------------------------------

    function testInitialMintAndFixedSupply() public view {
        assertEq(token.name(), DEFAULT_NAME);
        assertEq(token.symbol(), DEFAULT_SYMBOL);
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), INITIAL);
        assertEq(token.balanceOf(agent), INITIAL);
        assertEq(token.balanceOf(address(factory)), 0);
    }

    function testFactoryStamps() public view {
        assertEq(token.factory(), address(factory));
        assertEq(token.policy(), address(policy));
        assertEq(token.creator(), agent);
        assertEq(token.metadataURI(), DEFAULT_URI);
        assertTrue(token.assetType() == AssetType.FT);
    }

    function testDirectDeployReverts() public {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = agent;
        amounts[0] = 1;

        vm.expectRevert(abi.encodeWithSelector(AgenticToken.NotFactory.selector, address(this)));
        new AgenticToken(
            "Agent Token", "AGT", address(factory), address(policy), agent, recipients, amounts, DEFAULT_URI
        );
    }

    function testConstructorRejectsZeroPolicy() public {
        _expectConstructorRevert(
            address(0),
            agent,
            _addrArray(agent),
            _uintArray(1),
            abi.encodeWithSelector(AgenticToken.InvalidConfiguration.selector)
        );
    }

    function testConstructorRejectsZeroCreator() public {
        _expectConstructorRevert(
            address(policy),
            address(0),
            _addrArray(agent),
            _uintArray(1),
            abi.encodeWithSelector(AgenticToken.InvalidConfiguration.selector)
        );
    }

    function testConstructorRejectsLengthMismatch() public {
        address[] memory recipients = new address[](2);
        recipients[0] = agent;
        recipients[1] = agent2;
        _expectConstructorRevert(
            address(policy),
            agent,
            recipients,
            _uintArray(1),
            abi.encodeWithSelector(AgenticToken.LengthMismatch.selector)
        );
    }

    function testConstructorRejectsNoRecipients() public {
        _expectConstructorRevert(
            address(policy),
            agent,
            new address[](0),
            new uint256[](0),
            abi.encodeWithSelector(AgenticToken.NoInitialRecipients.selector)
        );
    }

    function testConstructorRejectsZeroRecipient() public {
        _expectConstructorRevert(
            address(policy),
            agent,
            _addrArray(address(0)),
            _uintArray(1),
            abi.encodeWithSelector(AgenticToken.ZeroRecipient.selector)
        );
    }

    function testConstructorRejectsZeroSupply() public {
        _expectConstructorRevert(
            address(policy),
            agent,
            _addrArray(agent),
            _uintArray(0),
            abi.encodeWithSelector(AgenticToken.NoInitialSupply.selector)
        );
    }

    // ---------------------------------------------------------------------
    // No mint / burn / pause / admin surface
    // ---------------------------------------------------------------------

    function testNoMintBurnPauseAdminSurface() public {
        assertFalse(_callSucceeds(address(token), abi.encodeWithSignature("mint(address,uint256)", agent, 1)));
        assertFalse(_callSucceeds(address(token), abi.encodeWithSignature("burn(uint256)", 1)));
        assertFalse(_callSucceeds(address(token), abi.encodeWithSignature("burnFrom(address,uint256)", agent, 1)));
        assertFalse(_callSucceeds(address(token), abi.encodeWithSignature("pause()")));
        assertFalse(_callSucceeds(address(token), abi.encodeWithSignature("unpause()")));
        assertFalse(_callSucceeds(address(token), abi.encodeWithSignature("owner()")));
        assertFalse(_callSucceeds(address(token), abi.encodeWithSignature("admin()")));
        assertFalse(_callSucceeds(address(token), abi.encodeWithSignature("setPolicy(address)", address(0))));
        assertFalse(_callSucceeds(address(token), abi.encodeWithSignature("setMetadataURI(string)", "ipfs://changed")));
        assertFalse(_callSucceeds(address(token), abi.encodeWithSignature("upgradeTo(address)", address(0xBEEF))));
        assertFalse(
            _callSucceeds(
                address(token), abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(0xBEEF), "")
            )
        );
        assertFalse(_callSucceeds(address(token), abi.encodeWithSignature("initialize()")));
        assertEq(token.metadataURI(), DEFAULT_URI);
    }

    function testFixedSupplyAfterTransfers() public {
        vm.prank(agent);
        token.transfer(agent2, 100 ether);
        vm.prank(agent2);
        token.transfer(address(game), 40 ether);

        assertEq(token.totalSupply(), INITIAL);
        assertEq(token.balanceOf(agent), 900 ether);
        assertEq(token.balanceOf(agent2), 60 ether);
        assertEq(token.balanceOf(address(game)), 40 ether);
    }

    // ---------------------------------------------------------------------
    // Real policy matrix
    // ---------------------------------------------------------------------

    function testTransferAgentToAgentAllowed() public {
        vm.prank(agent);
        assertTrue(token.transfer(agent2, 100 ether));
        assertEq(token.balanceOf(agent2), 100 ether);
    }

    function testTransferAgentToPoolAllowed() public {
        vm.prank(agent);
        assertTrue(token.transfer(address(pool), 10 ether));
        assertEq(token.balanceOf(address(pool)), 10 ether);
    }

    function testTransferAgentToPurposeAllowed() public {
        vm.prank(agent);
        assertTrue(token.transfer(address(game), 10 ether));
        assertEq(token.balanceOf(address(game)), 10 ether);
    }

    function testTransferAgentToCustodyDenied() public {
        vm.prank(agent);
        vm.expectRevert(_transferDenied("CATEGORY_DENIED"));
        token.transfer(address(vault), 1 ether);
    }

    function testTransferAgentToLpManagerDenied() public {
        vm.prank(agent);
        vm.expectRevert(_transferDenied("CATEGORY_DENIED"));
        token.transfer(address(lpManager), 1 ether);
    }

    function testTransferAgentToFeeRecipientDenied() public {
        vm.prank(agent);
        vm.expectRevert(_transferDenied("CATEGORY_DENIED"));
        token.transfer(address(feeRecipient), 1 ether);
    }

    function testTransferToZeroAddressDenied() public {
        // No burn path: OZ rejects the zero recipient before any balance move.
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidReceiver(address)", address(0)));
        token.transfer(address(0), 1);
        assertEq(token.totalSupply(), INITIAL);
    }

    function testTransferToNonAgentDenied() public {
        vm.prank(agent);
        vm.expectRevert(_transferDenied("NOT_ELIGIBLE"));
        token.transfer(nonAgent, 1 ether);
    }

    function testTransferFromAllowedBetweenAgents() public {
        vm.prank(agent);
        token.approve(agent2, 150 ether);

        vm.prank(agent2);
        assertTrue(token.transferFrom(agent, agent2, 150 ether));

        assertEq(token.balanceOf(agent), INITIAL - 150 ether);
        assertEq(token.balanceOf(agent2), 150 ether);
        assertEq(token.allowance(agent, agent2), 0);
    }

    function testTransferFromToNonAgentDenied() public {
        vm.prank(agent);
        token.approve(agent2, 150 ether);

        vm.prank(agent2);
        vm.expectRevert(_transferDenied("NOT_ELIGIBLE"));
        token.transferFrom(agent, nonAgent, 1 ether);
    }

    function testCustodyCanSendToAgent() public {
        AgenticToken facilityToken = AgenticToken(_createTokenFor(projectOwner, address(vault), 500 ether));

        vm.prank(address(vault));
        assertTrue(facilityToken.transfer(agent, 200 ether));
        assertEq(facilityToken.balanceOf(agent), 200 ether);
    }

    function testFacilityToFacilityDenied() public {
        AgenticToken facilityToken = AgenticToken(_createTokenFor(projectOwner, address(vault), 500 ether));

        vm.prank(address(vault));
        vm.expectRevert(_transferDenied("FACILITY_TO_FACILITY"));
        facilityToken.transfer(address(game), 1 ether);
    }

    function testRevokedFacilityIsFrozenThenReplacementAllowed() public {
        AgenticToken facilityToken = AgenticToken(_createTokenFor(projectOwner, address(vault), 500 ether));

        venue.revokeFacility(address(vault));

        vm.prank(address(vault));
        vm.expectRevert(_transferDenied("REVOKED_FACILITY"));
        facilityToken.transfer(agent, 1 ether);

        vm.prank(projectOwner);
        venue.setReplacement(address(vault), address(vault2));

        vm.prank(address(vault));
        assertTrue(facilityToken.transfer(address(vault2), 100 ether));
        assertEq(facilityToken.balanceOf(address(vault2)), 100 ether);
    }

    // ---------------------------------------------------------------------
    // Policy call shape / deny reason with a local mock
    // ---------------------------------------------------------------------

    function testPolicyGateArgsAreExact() public {
        MockTransferPolicy mockPolicy = new MockTransferPolicy();
        AgenticToken mockToken = _deployWithMockPolicy(mockPolicy);

        mockPolicy.setExpectedArgs(address(mockToken), agent, keccak256(abi.encode(TransferKind.TRANSFER)));

        vm.prank(agent);
        assertTrue(mockToken.transfer(agent2, 10));
    }

    function testPolicyGateTransferFromOperatorIsSpender() public {
        MockTransferPolicy mockPolicy = new MockTransferPolicy();
        AgenticToken mockToken = _deployWithMockPolicy(mockPolicy);

        mockPolicy.setExpectedArgs(address(mockToken), agent2, keccak256(abi.encode(TransferKind.TRANSFER)));

        vm.prank(agent);
        mockToken.approve(agent2, 10);

        vm.prank(agent2);
        assertTrue(mockToken.transferFrom(agent, agent2, 10));
    }

    function testPolicyDenyRevertsWithReason() public {
        MockTransferPolicy mockPolicy = new MockTransferPolicy();
        AgenticToken mockToken = _deployWithMockPolicy(mockPolicy);

        bytes32 reason = keccak256("MOCK_DENY");
        mockPolicy.setAllowed(false, reason);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticToken.TransferDenied.selector, reason));
        mockToken.transfer(agent2, 1);
    }

    function testPolicyDenyDuringMintRevertsConstruction() public {
        MockTransferPolicy mockPolicy = new MockTransferPolicy();
        mockPolicy.setAllowed(false, keccak256("MINT_DENIED"));

        address[] memory recipients = _addrArray(agent);
        uint256[] memory amounts = _uintArray(1);

        vm.expectRevert(abi.encodeWithSelector(AgenticToken.TransferDenied.selector, keccak256("MINT_DENIED")));
        new AgenticToken(
            "Agent Token", "AGT", address(this), address(mockPolicy), agent, recipients, amounts, DEFAULT_URI
        );
    }

    // ---------------------------------------------------------------------
    // Policy versioning
    // ---------------------------------------------------------------------

    function testPolicyIsImmutableAcrossCurrentPolicyChange() public {
        AgenticPolicy policy2 = new AgenticPolicy(address(identityRegistry), address(venue));
        policyRegistry.addPolicy(address(policy2), 2);
        policyRegistry.setCurrentPolicy(address(policy2));

        AgenticToken newer = _createRegisteredToken();
        assertEq(newer.policy(), address(policy2));

        // The first token keeps policy v1 and remains functional after v1 is
        // deprecated for new tokens.
        policyRegistry.deprecatePolicy(address(policy));
        assertEq(token.policy(), address(policy));
        assertTrue(policyRegistry.isPolicyAllowed(address(policy2)));

        vm.prank(agent);
        assertTrue(token.transfer(agent2, 1 ether));
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _deployWithMockPolicy(MockTransferPolicy mockPolicy) internal returns (AgenticToken mockToken) {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        recipients[0] = agent;
        recipients[1] = agent2;
        amounts[0] = 100;
        amounts[1] = 100;

        mockToken = new AgenticToken(
            "Mock Gated", "MGT", address(this), address(mockPolicy), agent, recipients, amounts, DEFAULT_URI
        );
    }

    function _expectConstructorRevert(
        address policy_,
        address creator_,
        address[] memory recipients,
        uint256[] memory amounts,
        bytes memory revertData
    ) internal {
        vm.expectRevert(revertData);
        new AgenticToken("Agent Token", "AGT", address(this), policy_, creator_, recipients, amounts, DEFAULT_URI);
    }

    function _addrArray(address value) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = value;
    }

    function _uintArray(uint256 value) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = value;
    }

    function _transferDenied(string memory reason) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AgenticToken.TransferDenied.selector, keccak256(bytes(reason)));
    }

    function _callSucceeds(address target, bytes memory data) internal returns (bool ok) {
        (ok,) = target.call(data);
    }
}
