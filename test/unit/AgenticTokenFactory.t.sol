// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {AgenticPolicy} from "../../contracts/policy/AgenticPolicy.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";
import {AgenticTokenFactory} from "../../contracts/token/AgenticTokenFactory.sol";
import {AgenticAssetRegistry} from "../../contracts/registry/AgenticAssetRegistry.sol";
import {AgenticPolicyRegistry} from "../../contracts/policy/AgenticPolicyRegistry.sol";
import {IAgentTokenFactory} from "../../contracts/interfaces/IAgentTokenFactory.sol";
import {IAgentToken} from "../../contracts/interfaces/IAgentAsset.sol";
import {AssetType, FacilityCategory} from "../../contracts/common/Types.sol";
import {MockPolicy} from "../mocks/MockPolicy.sol";
import {TokenAssetFixture} from "../helpers/TokenAssetFixture.sol";

contract AgenticTokenFactoryTest is TokenAssetFixture {
    uint256 internal constant AMOUNT = 1_000 ether;

    function setUp() public {
        _deployTokenAsset();
    }

    // ---------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------

    function testConstructorStamps() public view {
        assertEq(factory.policyRegistry(), address(policyRegistry));
        assertEq(factory.assetRegistry(), address(assetRegistry));
        assertEq(factory.facilityRegistry(), address(venue));
        assertEq(factory.maxRecipients(), MAX_RECIPIENTS);
    }

    function testConstructorRejectsZeroRegistries() public {
        vm.expectRevert(AgenticTokenFactory.ZeroRegistry.selector);
        new AgenticTokenFactory(address(0), address(assetRegistry), address(venue), MAX_RECIPIENTS);

        vm.expectRevert(AgenticTokenFactory.ZeroRegistry.selector);
        new AgenticTokenFactory(address(policyRegistry), address(0), address(venue), MAX_RECIPIENTS);

        vm.expectRevert(AgenticTokenFactory.ZeroRegistry.selector);
        new AgenticTokenFactory(address(policyRegistry), address(assetRegistry), address(0), MAX_RECIPIENTS);
    }

    function testConstructorRejectsCodelessRegistries() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticTokenFactory.RegistryHasNoCode.selector, nonAgent));
        new AgenticTokenFactory(nonAgent, address(assetRegistry), address(venue), MAX_RECIPIENTS);

        vm.expectRevert(abi.encodeWithSelector(AgenticTokenFactory.RegistryHasNoCode.selector, nonAgent));
        new AgenticTokenFactory(address(policyRegistry), nonAgent, address(venue), MAX_RECIPIENTS);

        vm.expectRevert(abi.encodeWithSelector(AgenticTokenFactory.RegistryHasNoCode.selector, nonAgent));
        new AgenticTokenFactory(address(policyRegistry), address(assetRegistry), nonAgent, MAX_RECIPIENTS);
    }

    function testConstructorRejectsZeroMaxRecipients() public {
        vm.expectRevert(AgenticTokenFactory.InvalidMaxRecipients.selector);
        new AgenticTokenFactory(address(policyRegistry), address(assetRegistry), address(venue), 0);
    }

    // ---------------------------------------------------------------------
    // Permissionless creation and registry stamps
    // ---------------------------------------------------------------------

    function testCreateTokenByAgent() public {
        address token = _createTokenFor(agent, agent, AMOUNT);
        AgenticToken gated = AgenticToken(token);

        assertEq(gated.name(), DEFAULT_NAME);
        assertEq(gated.symbol(), DEFAULT_SYMBOL);
        assertEq(gated.decimals(), 18);
        assertEq(gated.totalSupply(), AMOUNT);
        assertEq(gated.balanceOf(agent), AMOUNT);
        assertEq(gated.balanceOf(address(factory)), 0);
        assertEq(gated.factory(), address(factory));
        assertEq(gated.policy(), address(policy));
        assertEq(gated.creator(), agent);
        assertEq(gated.metadataURI(), DEFAULT_URI);
        assertTrue(gated.assetType() == AssetType.FT);

        assertTrue(assetRegistry.isRegistered(token));
        assertEq(assetRegistry.policyOf(token), address(policy));
        assertEq(assetRegistry.creatorOf(token), agent);
        assertEq(assetRegistry.poolsOf(token).length, 0);
    }

    function testCreateTokenByProjectWithoutIdentity() public {
        // A project EOA needs no Agent ID: only the recipients are gated.
        address token = _createTokenFor(projectOwner, agent, AMOUNT);

        assertEq(AgenticToken(token).creator(), projectOwner);
        assertEq(assetRegistry.creatorOf(token), projectOwner);
        assertEq(AgenticToken(token).balanceOf(agent), AMOUNT);
        assertFalse(policy.isMember(projectOwner));
    }

    function testTokenCreatedEvent() public {
        vm.recordLogs();
        address token = _createTokenFor(agent, agent, AMOUNT);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 topic = keccak256("TokenCreated(address,address,address)");
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(factory) || logs[i].topics[0] != topic) continue;
            assertEq(address(uint160(uint256(logs[i].topics[1]))), token);
            assertEq(address(uint160(uint256(logs[i].topics[2]))), agent);
            assertEq(address(uint160(uint256(logs[i].topics[3]))), address(policy));
            found = true;
        }
        assertTrue(found);
    }

    function testCreateTokenThroughFrozenInterface() public {
        IAgentTokenFactory gated = IAgentTokenFactory(address(factory));
        address[] memory recipients = _addrArray(agent);
        uint256[] memory amounts = _uintArray(AMOUNT);

        vm.prank(agent);
        address token = gated.createToken(DEFAULT_NAME, DEFAULT_SYMBOL, address(0), recipients, amounts, DEFAULT_URI);

        assertTrue(assetRegistry.isRegistered(token));
        assertEq(IAgentToken(token).factory(), address(factory));
    }

    function testCreateTokenSelectorIsFrozen() public pure {
        assertEq(
            IAgentTokenFactory.createToken.selector,
            bytes4(keccak256("createToken(string,string,address,address[],uint256[],string)"))
        );
        assertEq(AgenticTokenFactory.createToken.selector, IAgentTokenFactory.createToken.selector);
    }

    // ---------------------------------------------------------------------
    // Policy resolution
    // ---------------------------------------------------------------------

    function testPolicyZeroResolvesCurrentPolicy() public {
        address token = _createTokenFor(agent, agent, AMOUNT);
        assertEq(AgenticToken(token).policy(), address(policy));
        assertEq(assetRegistry.policyOf(token), address(policy));
    }

    function testExplicitAllowedPolicy() public {
        address token = _createToken(agent, address(policy), _addrArray(agent), _uintArray(AMOUNT), DEFAULT_URI);
        assertEq(AgenticToken(token).policy(), address(policy));
    }

    function testUnregisteredPolicyRejected() public {
        MockPolicy unknown = new MockPolicy(9);
        vm.expectRevert(abi.encodeWithSelector(AgenticTokenFactory.PolicyNotAllowed.selector, address(unknown)));
        _createToken(agent, address(unknown), _addrArray(agent), _uintArray(AMOUNT), DEFAULT_URI);
    }

    function testDeprecatedPolicyRejected() public {
        AgenticPolicy policy2 = new AgenticPolicy(address(identityRegistry), address(venue));
        policyRegistry.addPolicy(address(policy2), 2);
        policyRegistry.setCurrentPolicy(address(policy2));
        policyRegistry.deprecatePolicy(address(policy));

        vm.expectRevert(abi.encodeWithSelector(AgenticTokenFactory.PolicyNotAllowed.selector, address(policy)));
        _createToken(agent, address(policy), _addrArray(agent), _uintArray(AMOUNT), DEFAULT_URI);
    }

    function testZeroCurrentPolicyRejected() public {
        AgenticPolicyRegistry emptyRegistry = new AgenticPolicyRegistry(address(this), 1);
        AgenticTokenFactory emptyFactory =
            new AgenticTokenFactory(address(emptyRegistry), address(assetRegistry), address(venue), MAX_RECIPIENTS);
        assetRegistry.setRegistrar(address(emptyFactory), true);

        address[] memory recipients = _addrArray(agent);
        uint256[] memory amounts = _uintArray(AMOUNT);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticTokenFactory.PolicyNotAllowed.selector, address(0)));
        emptyFactory.createToken(DEFAULT_NAME, DEFAULT_SYMBOL, address(0), recipients, amounts, DEFAULT_URI);
    }

    // ---------------------------------------------------------------------
    // Recipient matrix
    // ---------------------------------------------------------------------

    function testCustodyAndPurposeRecipientsAllowed() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        recipients[0] = address(vault);
        recipients[1] = address(game);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;

        address token = _createToken(projectOwner, address(0), recipients, amounts, DEFAULT_URI);

        assertEq(AgenticToken(token).balanceOf(address(vault)), 100 ether);
        assertEq(AgenticToken(token).balanceOf(address(game)), 200 ether);
        assertEq(AgenticToken(token).totalSupply(), 300 ether);
    }

    function testMixedAgentAndFacilityRecipients() public {
        address[] memory recipients = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        recipients[0] = agent;
        recipients[1] = address(vault);
        recipients[2] = address(game);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;
        amounts[2] = 300 ether;

        address token = _createToken(projectOwner, address(0), recipients, amounts, DEFAULT_URI);

        assertEq(AgenticToken(token).totalSupply(), 600 ether);
        assertEq(AgenticToken(token).balanceOf(agent), 100 ether);
        assertEq(AgenticToken(token).balanceOf(address(vault)), 200 ether);
        assertEq(AgenticToken(token).balanceOf(address(game)), 300 ether);
    }

    function testPoolRecipientRejected() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticTokenFactory.RecipientCategoryNotAllowed.selector, address(pool), FacilityCategory.POOL
            )
        );
        _createTokenFor(agent, address(pool), 1);
    }

    function testLpManagerRecipientRejected() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticTokenFactory.RecipientCategoryNotAllowed.selector,
                address(lpManager),
                FacilityCategory.LP_MANAGER
            )
        );
        _createTokenFor(agent, address(lpManager), 1);
    }

    function testFeeRecipientRecipientRejected() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticTokenFactory.RecipientCategoryNotAllowed.selector,
                address(feeRecipient),
                FacilityCategory.FEE_RECIPIENT
            )
        );
        _createTokenFor(agent, address(feeRecipient), 1);
    }

    function testNonAgentRecipientRejected() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticTokenFactory.RecipientNotEligible.selector, nonAgent));
        _createTokenFor(agent, nonAgent, 1);
    }

    function testZeroRecipientRejected() public {
        vm.expectRevert(AgenticTokenFactory.ZeroRecipient.selector);
        _createTokenFor(agent, address(0), 1);
    }

    function testDuplicateRecipientRejected() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        recipients[0] = agent;
        recipients[1] = agent;
        amounts[0] = 1;
        amounts[1] = 2;

        vm.expectRevert(abi.encodeWithSelector(AgenticTokenFactory.DuplicateRecipient.selector, agent));
        _createToken(agent, address(0), recipients, amounts, DEFAULT_URI);
    }

    function testRevokedCustodyRecipientRejected() public {
        venue.revokeFacility(address(vault));

        vm.expectRevert(abi.encodeWithSelector(AgenticTokenFactory.RecipientNotActiveFacility.selector, address(vault)));
        _createTokenFor(projectOwner, address(vault), 1);
    }

    function testRevokedPurposeRecipientRejected() public {
        venue.revokeFacility(address(game));

        vm.expectRevert(abi.encodeWithSelector(AgenticTokenFactory.RecipientNotActiveFacility.selector, address(game)));
        _createTokenFor(projectOwner, address(game), 1);
    }

    // ---------------------------------------------------------------------
    // Lengths, counts and supply
    // ---------------------------------------------------------------------

    function testLengthMismatchRejected() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = agent;
        recipients[1] = agent2;
        amounts[0] = 1;

        vm.expectRevert(AgenticTokenFactory.LengthMismatch.selector);
        _createToken(agent, address(0), recipients, amounts, DEFAULT_URI);
    }

    function testNoRecipientsRejected() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticTokenFactory.InvalidRecipientCount.selector, 0, MAX_RECIPIENTS));
        _createToken(agent, address(0), new address[](0), new uint256[](0), DEFAULT_URI);
    }

    function testRecipientCapRejected() public {
        address[] memory recipients = new address[](MAX_RECIPIENTS + 1);
        uint256[] memory amounts = new uint256[](MAX_RECIPIENTS + 1);
        for (uint256 i; i < recipients.length; ++i) {
            recipients[i] = address(uint160(0x1000 + i));
            amounts[i] = 1;
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticTokenFactory.InvalidRecipientCount.selector, MAX_RECIPIENTS + 1, MAX_RECIPIENTS
            )
        );
        _createToken(agent, address(0), recipients, amounts, DEFAULT_URI);
    }

    function testMaxRecipientsBoundaryAllowed() public {
        address[] memory recipients = _eligibleRecipients();
        uint256[] memory amounts = new uint256[](MAX_RECIPIENTS);
        for (uint256 i; i < MAX_RECIPIENTS; ++i) {
            amounts[i] = 1 ether;
        }

        address token = _createToken(agent, address(0), recipients, amounts, DEFAULT_URI);

        assertEq(AgenticToken(token).totalSupply(), MAX_RECIPIENTS * 1 ether);
    }

    function testZeroTotalSupplyRejected() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        recipients[0] = agent;
        recipients[1] = agent2;
        amounts[0] = 0;
        amounts[1] = 0;

        vm.expectRevert(AgenticTokenFactory.ZeroInitialSupply.selector);
        _createToken(agent, address(0), recipients, amounts, DEFAULT_URI);
    }

    // ---------------------------------------------------------------------
    // Atomic registration and no direct deployment
    // ---------------------------------------------------------------------

    function testCreationRevertsWhenFactoryIsNotAssetRegistrar() public {
        assetRegistry.setRegistrar(address(factory), false);

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(AgenticAssetRegistry.NotRegistrar.selector, address(factory)));
        _createTokenFor(agent, agent, AMOUNT);

        // The whole creation reverted before the success event was emitted.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 tokenCreated = keccak256("TokenCreated(address,address,address)");
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != tokenCreated);
        }
    }

    function testDirectTokenDeploymentReverts() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticToken.NotFactory.selector, address(this)));
        new AgenticToken(
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            address(factory),
            address(policy),
            agent,
            _addrArray(agent),
            _uintArray(AMOUNT),
            DEFAULT_URI
        );
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _addrArray(address value) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = value;
    }

    function _uintArray(uint256 value) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = value;
    }
}
