// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import {AgentswapPositionManager} from "../../contracts/AgentswapPositionManager.sol";
import {INonfungiblePositionManager} from "../../contracts/interfaces/INonfungiblePositionManager.sol";
import {PoolAddress} from "../../contracts/libraries/PoolAddress.sol";

import {TestBase} from "../helpers/TestBase.sol";
import {MockAssetRegistry} from "../mocks/MockAssetRegistry.sol";
import {MockTransferPolicy} from "../mocks/MockTransferPolicy.sol";

/// @notice the NPM NPM gate tests: per-token policy resolution, Agent-only LP
/// NFT mint/transfer/ops/collect, no facility LP, public-token passthrough.
/// @dev The protocol registries are mocked and the V3 pool is a mock etched at the
/// exact CREATE2 address the NPM computes, so the unmodified NPM addLiquidity /
/// position accounting paths run without real AMM math or token transfers.
contract NPMGateTest is TestBase {
    uint24 private constant FEE = 3000;
    int24 private constant MIN_TICK = -887220;
    int24 private constant MAX_TICK = 887220;
    uint256 private constant MINT_AMOUNT = 1e18;

    uint8 private constant CAT_NONE = 0;
    uint8 private constant CAT_POOL = 1;
    uint8 private constant CAT_LP_MANAGER = 2;
    uint8 private constant CAT_FEE_RECIPIENT = 3;
    uint8 private constant CAT_CUSTODY = 4;
    uint8 private constant CAT_PURPOSE = 5;

    bytes4 private constant ERR_NOT_AGENT = bytes4(keccak256("NotAgent()"));
    bytes4 private constant ERR_OWNER_CALLER = bytes4(keccak256("NotAgentOwnerOrCaller()"));
    bytes4 private constant ERR_TRANSFER = bytes4(keccak256("NotAgentTransfer()"));
    bytes4 private constant ERR_ASSET_REGISTRY = bytes4(keccak256("AssetRegistryHasNoCode()"));

    address private constant AGENT = address(0xA11CE);
    address private constant AGENT_B = address(0xB0B);
    address private constant AGENT_A_ONLY = address(0xAAA);
    address private constant NON_AGENT = address(0xBAD);
    address private constant FACILITY = address(0xFAC11);
    address private constant FACILITY_POOL = address(0xF001);

    address private factory;
    MockAssetRegistry private registry;
    AgentswapPositionManager private npm;

    MockTransferPolicy private policyGated;
    MockTransferPolicy private policyA;
    MockTransferPolicy private policyB;

    /// @dev Sorted token addresses per pool: gated/quote, gated/gated, public.
    address private gq0;
    address private gq1;
    address private gg0;
    address private gg1;
    address private pp0;
    address private pp1;

    address private gatedToken;
    address private gatedAToken;
    address private gatedBToken;

    function setUp() public {
        factory = address(0xFACA);
        registry = new MockAssetRegistry();
        npm = AgentswapPositionManager(_deployNpm(address(registry)));

        gatedToken = address(0x1001);
        address quoteToken = address(0x1002);
        gatedAToken = address(0x2001);
        gatedBToken = address(0x2002);
        address publicA = address(0x3001);
        address publicB = address(0x3002);

        (gq0, gq1) = _sort(gatedToken, quoteToken);
        (gg0, gg1) = _sort(gatedAToken, gatedBToken);
        (pp0, pp1) = _sort(publicA, publicB);

        policyGated = new MockTransferPolicy();
        policyA = new MockTransferPolicy();
        policyB = new MockTransferPolicy();
        _configurePolicy(policyGated);
        _configurePolicy(policyA);
        _configurePolicy(policyB);

        registry.setRegistered(gatedToken, true);
        registry.setPolicy(gatedToken, address(policyGated));
        registry.setRegistered(gatedAToken, true);
        registry.setPolicy(gatedAToken, address(policyA));
        registry.setRegistered(gatedBToken, true);
        registry.setPolicy(gatedBToken, address(policyB));

        _etchPool(gq0, gq1);
        _etchPool(gg0, gg1);
        _etchPool(pp0, pp1);
    }

    // ---------------------------------------------------------------------
    // Constructor / policy resolution
    // ---------------------------------------------------------------------

    function testConstructorRejectsZeroAssetRegistry() public {
        assertEq(_createNpm(address(0)), address(0));
    }

    function testConstructorRejectsCodelessAssetRegistry() public {
        assertEq(_createNpm(address(0x1234)), address(0));
    }

    function testPolicyOfTokenResolvesPerToken() public {
        assertEq(npm.policyOfToken(gatedToken), address(policyGated));
        assertEq(npm.policyOfToken(gatedAToken), address(policyA));
        assertEq(npm.policyOfToken(gatedBToken), address(policyB));
        assertEq(npm.policyOfToken(gq0 == gatedToken ? gq1 : gq0), address(0));
    }

    function testIsAllowedRecipientPublicTokenIsUnrestricted() public {
        address publicToken = pp0;
        assertTrue(npm.isAllowedRecipient(publicToken, AGENT));
        assertTrue(npm.isAllowedRecipient(publicToken, NON_AGENT));
        assertTrue(npm.isAllowedRecipient(publicToken, FACILITY));
        assertTrue(npm.isAllowedRecipient(publicToken, address(this)));
    }

    function testIsAllowedRecipientGatedAgent() public {
        assertTrue(npm.isAllowedRecipient(gatedToken, AGENT));
        assertTrue(npm.isAllowedRecipient(gatedToken, address(this)));
    }

    function testIsAllowedRecipientGatedNonAgent() public {
        assertFalse(npm.isAllowedRecipient(gatedToken, NON_AGENT));
        assertFalse(npm.isAllowedRecipient(gatedToken, FACILITY));
        assertFalse(npm.isAllowedRecipient(gatedToken, address(npm)));
    }

    function testIsAllowedRecipientRejectsEveryFacilityCategory() public {
        for (uint8 category = CAT_POOL; category <= CAT_PURPOSE; category++) {
            policyGated.setMember(NON_AGENT, true);
            policyGated.setCategory(NON_AGENT, category);
            assertFalse(npm.isAllowedRecipient(gatedToken, NON_AGENT));
        }
        // Membership alone is not enough; a facility category always denies.
        policyGated.setCategory(NON_AGENT, CAT_PURPOSE);
        policyGated.setMember(NON_AGENT, true);
        assertFalse(npm.isAllowedRecipient(gatedToken, NON_AGENT));
    }

    function testIsAllowedTransferSkipsZeroSides() public {
        uint256 tokenId = _mintGatedGated(AGENT);

        assertTrue(npm.isAllowedTransfer(tokenId, address(0), AGENT));
        assertTrue(npm.isAllowedTransfer(tokenId, AGENT, address(0)));
        assertFalse(npm.isAllowedTransfer(tokenId, address(0), NON_AGENT));
        assertFalse(npm.isAllowedTransfer(tokenId, NON_AGENT, address(0)));
    }

    function testIsAllowedTransferGatedGatedChecksBothPolicies() public {
        uint256 tokenId = _mintGatedGated(AGENT);

        // AGENT_B is a member of policyA only; policyB still denies.
        policyA.setMember(AGENT_B, true);
        assertFalse(npm.isAllowedTransfer(tokenId, AGENT, AGENT_B));

        policyB.setMember(AGENT_B, true);
        assertTrue(npm.isAllowedTransfer(tokenId, AGENT, AGENT_B));
    }

    function testIsAllowedTransferGatedGatedRejectsFacilitySides() public {
        uint256 tokenId = _mintGatedGated(AGENT);
        assertFalse(npm.isAllowedTransfer(tokenId, FACILITY, AGENT));
        assertFalse(npm.isAllowedTransfer(tokenId, AGENT, FACILITY));
    }

    function testIsAllowedTransferInvalidTokenReturnsFalse() public {
        assertFalse(npm.isAllowedTransfer(0, AGENT, AGENT));
        assertFalse(npm.isAllowedTransfer(999, AGENT, AGENT));
    }

    // ---------------------------------------------------------------------
    // Mint
    // ---------------------------------------------------------------------

    function testMintGatedToAgentWorks() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        assertEq(npm.ownerOf(tokenId), AGENT);
        assertTrue(_positionLiquidity(tokenId) > 0);
    }

    function testMintGatedToNonAgentReverts() public {
        expectRevertSelector(ERR_NOT_AGENT);
        _mintGatedQuote(NON_AGENT);
    }

    function testMintGatedToFacilityReverts() public {
        expectRevertSelector(ERR_NOT_AGENT);
        _mintGatedQuote(FACILITY);
    }

    function testMintGatedCallerNonAgentReverts() public {
        vm.prank(NON_AGENT);
        expectRevertSelector(ERR_NOT_AGENT);
        _mintGatedQuote(AGENT);
    }

    function testMintGatedCallerFacilityReverts() public {
        vm.prank(FACILITY);
        expectRevertSelector(ERR_NOT_AGENT);
        _mintGatedQuote(AGENT);
    }

    function testMintGatedGatedBothPolicies() public {
        uint256 tokenId = _mintGatedGated(AGENT);
        assertEq(npm.ownerOf(tokenId), AGENT);

        // Member of policyA only: the second gated token denies the recipient.
        policyA.setMember(AGENT_A_ONLY, true);
        expectRevertSelector(ERR_NOT_AGENT);
        _mintGatedGated(AGENT_A_ONLY);
    }

    function testMintGatedGatedCallerChecksBothPolicies() public {
        policyA.setMember(AGENT_A_ONLY, true);
        // Recipient AGENT passes both policies; the caller is a member of A only.
        vm.prank(AGENT_A_ONLY);
        expectRevertSelector(ERR_NOT_AGENT);
        _mintGatedGated(AGENT);
    }

    function testMintOneGatedOneQuote() public {
        // Gated/quote: only the gated side is checked.
        assertEq(npm.policyOfToken(gatedToken), address(policyGated));
        assertEq(npm.policyOfToken(gq0 == gatedToken ? gq1 : gq0), address(0));
        uint256 tokenId = _mintGatedQuote(AGENT);
        assertEq(npm.ownerOf(tokenId), AGENT);

        expectRevertSelector(ERR_NOT_AGENT);
        _mintGatedQuote(NON_AGENT);
    }

    function testMintPublicPoolByNonAgentWorks() public {
        vm.prank(NON_AGENT);
        uint256 tokenId = _mintPublic(NON_AGENT);
        assertEq(npm.ownerOf(tokenId), NON_AGENT);
    }

    function testMintPublicPoolNotGated() public {
        uint256 tokenId = _mintPublic(NON_AGENT);
        assertEq(npm.ownerOf(tokenId), NON_AGENT);

        vm.prank(NON_AGENT);
        npm.transferFrom(NON_AGENT, FACILITY, tokenId);
        assertEq(npm.ownerOf(tokenId), FACILITY);
    }

    // ---------------------------------------------------------------------
    // LP NFT transfer / burn hook
    // ---------------------------------------------------------------------

    function testTransferGatedAgentToAgentWorks() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        policyGated.setMember(AGENT_B, true);

        vm.prank(AGENT);
        npm.transferFrom(AGENT, AGENT_B, tokenId);
        assertEq(npm.ownerOf(tokenId), AGENT_B);
        assertTrue(npm.isAllowedTransfer(tokenId, AGENT, AGENT_B));
    }

    function testTransferByNonAgentApprovedOperatorReverts() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        policyGated.setMember(AGENT_B, true);

        vm.prank(AGENT);
        npm.approve(NON_AGENT, tokenId);

        vm.prank(NON_AGENT);
        expectRevertSelector(ERR_TRANSFER);
        npm.transferFrom(AGENT, AGENT_B, tokenId);
    }

    function testTransferGatedToNonAgentReverts() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        vm.prank(AGENT);
        expectRevertSelector(ERR_TRANSFER);
        npm.transferFrom(AGENT, NON_AGENT, tokenId);
    }

    function testTransferGatedToFacilityReverts() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        vm.prank(AGENT);
        expectRevertSelector(ERR_TRANSFER);
        npm.transferFrom(AGENT, FACILITY, tokenId);
    }

    function testSafeTransferGatedToNonAgentReverts() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        vm.prank(AGENT);
        expectRevertSelector(ERR_TRANSFER);
        npm.safeTransferFrom(AGENT, NON_AGENT, tokenId);
    }

    function testTransferGatedFromAgentAfterMembershipRevokedReverts() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        policyGated.setMember(AGENT_B, true);
        policyGated.setMember(AGENT, false);

        vm.prank(AGENT);
        expectRevertSelector(ERR_TRANSFER);
        npm.transferFrom(AGENT, AGENT_B, tokenId);
    }

    function testTransferGatedGatedChecksBothPolicies() public {
        uint256 tokenId = _mintGatedGated(AGENT);
        policyA.setMember(AGENT_B, true);

        vm.prank(AGENT);
        expectRevertSelector(ERR_TRANSFER);
        npm.transferFrom(AGENT, AGENT_B, tokenId);

        policyB.setMember(AGENT_B, true);
        vm.prank(AGENT);
        npm.transferFrom(AGENT, AGENT_B, tokenId);
        assertEq(npm.ownerOf(tokenId), AGENT_B);
    }

    // ---------------------------------------------------------------------
    // Increase / decrease / burn owner+caller gates
    // ---------------------------------------------------------------------

    function testIncreaseLiquidityAgentOwnerAndCallerWorks() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        uint128 before = _positionLiquidity(tokenId);

        _increase(tokenId, address(this), MINT_AMOUNT, MINT_AMOUNT);
        assertTrue(_positionLiquidity(tokenId) > before);
    }

    function testIncreaseLiquidityNonAgentCallerReverts() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        expectRevertSelector(ERR_OWNER_CALLER);
        _increase(tokenId, NON_AGENT, MINT_AMOUNT, MINT_AMOUNT);
    }

    function testIncreaseLiquidityNonAgentOwnerReverts() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        policyGated.setMember(AGENT, false);

        expectRevertSelector(ERR_OWNER_CALLER);
        _increase(tokenId, address(this), MINT_AMOUNT, MINT_AMOUNT);
    }

    function testDecreaseLiquidityAgentOwnerWorks() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        uint128 liquidity = _positionLiquidity(tokenId);

        vm.prank(AGENT);
        npm.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId, liquidity: liquidity / 2, amount0Min: 0, amount1Min: 0, deadline: uint256(-1)
            })
        );
        assertTrue(_positionLiquidity(tokenId) < liquidity);
    }

    function testDecreaseLiquidityNonAgentCallerReverts() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        uint128 liquidity = _positionLiquidity(tokenId);
        vm.prank(AGENT);
        npm.approve(NON_AGENT, tokenId);

        expectRevertSelector(ERR_OWNER_CALLER);
        _decrease(tokenId, NON_AGENT, liquidity / 2);
    }

    function testDecreaseLiquidityNonAgentOwnerReverts() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        uint128 liquidity = _positionLiquidity(tokenId);
        policyGated.setMember(AGENT, false);
        vm.prank(AGENT);
        npm.approve(address(this), tokenId);

        expectRevertSelector(ERR_OWNER_CALLER);
        npm.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId, liquidity: liquidity / 2, amount0Min: 0, amount1Min: 0, deadline: uint256(-1)
            })
        );
    }

    function testBurnAgentOwnerWorks() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        _clearPosition(tokenId, AGENT);

        vm.prank(AGENT);
        npm.burn(tokenId);
        assertFalse(_positionExists(tokenId));
    }

    function testBurnNonAgentCallerReverts() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        _clearPosition(tokenId, AGENT);
        vm.prank(AGENT);
        npm.approve(NON_AGENT, tokenId);

        vm.prank(NON_AGENT);
        expectRevertSelector(ERR_OWNER_CALLER);
        npm.burn(tokenId);
    }

    function testBurnNonAgentOwnerReverts() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        _clearPosition(tokenId, AGENT);
        policyGated.setMember(AGENT, false);
        vm.prank(AGENT);
        npm.approve(address(this), tokenId);

        expectRevertSelector(ERR_OWNER_CALLER);
        npm.burn(tokenId);
    }

    // ---------------------------------------------------------------------
    // Collect
    // ---------------------------------------------------------------------

    function testCollectAgentRecipientWorks() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        _decrease(tokenId, AGENT, _positionLiquidity(tokenId));

        (uint256 amount0, uint256 amount1) = _collect(tokenId, AGENT, AGENT);
        assertTrue(amount0 > 0 || amount1 > 0);
        (uint128 owed0, uint128 owed1) = _tokensOwed(tokenId);
        assertEq(uint256(owed0), 0);
        assertEq(uint256(owed1), 0);
    }

    function testCollectNonAgentRecipientReverts() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        _decrease(tokenId, AGENT, _positionLiquidity(tokenId));

        vm.prank(AGENT);
        expectRevertSelector(ERR_NOT_AGENT);
        npm.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId, recipient: NON_AGENT, amount0Max: uint128(-1), amount1Max: uint128(-1)
            })
        );
    }

    function testCollectFacilityRecipientReverts() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        _decrease(tokenId, AGENT, _positionLiquidity(tokenId));

        vm.prank(AGENT);
        expectRevertSelector(ERR_NOT_AGENT);
        npm.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId, recipient: FACILITY, amount0Max: uint128(-1), amount1Max: uint128(-1)
            })
        );
    }

    function testCollectGatedGatedRecipientChecksBothPolicies() public {
        uint256 tokenId = _mintGatedGated(AGENT);
        _decrease(tokenId, AGENT, _positionLiquidity(tokenId));

        policyA.setMember(AGENT_A_ONLY, true);
        expectRevertSelector(ERR_NOT_AGENT);
        _collect(tokenId, AGENT, AGENT_A_ONLY);

        policyB.setMember(AGENT_A_ONLY, true);
        _collect(tokenId, AGENT, AGENT_A_ONLY);
    }

    function testCollectZeroRecipientRevertsForGated() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        _decrease(tokenId, AGENT, _positionLiquidity(tokenId));

        // recipient 0 resolves to the NPM itself, an LP_MANAGER facility.
        vm.prank(AGENT);
        expectRevertSelector(ERR_NOT_AGENT);
        npm.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId, recipient: address(0), amount0Max: uint128(-1), amount1Max: uint128(-1)
            })
        );
    }

    function testCollectNonAgentCallerReverts() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        _decrease(tokenId, AGENT, _positionLiquidity(tokenId));
        vm.prank(AGENT);
        npm.approve(NON_AGENT, tokenId);

        expectRevertSelector(ERR_OWNER_CALLER);
        _collect(tokenId, NON_AGENT, AGENT);
    }

    function testCollectNonAgentOwnerReverts() public {
        uint256 tokenId = _mintGatedQuote(AGENT);
        _decrease(tokenId, AGENT, _positionLiquidity(tokenId));
        policyGated.setMember(AGENT, false);
        vm.prank(AGENT);
        npm.approve(address(this), tokenId);

        expectRevertSelector(ERR_OWNER_CALLER);
        npm.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId, recipient: address(this), amount0Max: uint128(-1), amount1Max: uint128(-1)
            })
        );
    }

    // ---------------------------------------------------------------------
    // No admin path
    // ---------------------------------------------------------------------

    function testNoAdminSetters() public {
        (bool setRegistry,) = address(npm).call(abi.encodeWithSignature("setAssetRegistry(address)", address(1)));
        assertFalse(setRegistry);
        (bool setPolicy,) = address(npm).call(abi.encodeWithSignature("setPolicy(address)", address(1)));
        assertFalse(setPolicy);
        (bool setRecipient,) =
            address(npm).call(abi.encodeWithSignature("setAllowedRecipient(address,bool)", address(1)));
        assertFalse(setRecipient);

        // The attempted calls did not change per-token resolution.
        assertEq(npm.policyOfToken(gatedToken), address(policyGated));
        assertEq(npm.policyOfToken(gatedAToken), address(policyA));
    }

    // ---------------------------------------------------------------------
    // Fuzz
    // ---------------------------------------------------------------------

    function testFuzzIsAllowedRecipient(address account, bool member, uint8 category) public {
        category = uint8(category % 6);
        policyGated.setMember(account, member);
        policyGated.setCategory(account, category);

        bool expected = member && category == CAT_NONE;
        assertTrue(npm.isAllowedRecipient(gatedToken, account) == expected);
    }

    function testFuzzIsAllowedTransferTo(address to, bool member, uint8 category) public {
        vm.assume(to != address(0) && to != AGENT);
        category = uint8(category % 6);
        policyGated.setMember(to, member);
        policyGated.setCategory(to, category);

        uint256 tokenId = _mintGatedQuote(AGENT);
        bool expected = member && category == CAT_NONE;
        assertTrue(npm.isAllowedTransfer(tokenId, AGENT, to) == expected);
    }

    function testFuzzIsAllowedTransferFrom(address from, bool member, uint8 category) public {
        vm.assume(from != address(0) && from != AGENT);
        category = uint8(category % 6);
        policyGated.setMember(from, member);
        policyGated.setCategory(from, category);

        uint256 tokenId = _mintGatedQuote(AGENT);
        bool expected = member && category == CAT_NONE;
        assertTrue(npm.isAllowedTransfer(tokenId, from, AGENT) == expected);
    }

    function testFuzzFacilityCategoryNeverRecipient(address facility, uint8 category, bool member) public {
        category = uint8(CAT_POOL + (category % 5));
        policyGated.setMember(facility, member);
        policyGated.setCategory(facility, category);
        assertFalse(npm.isAllowedRecipient(gatedToken, facility));
    }

    function testFuzzMintNonAgentRecipientReverts(address recipient) public {
        vm.assume(recipient != AGENT && recipient != address(this));
        expectRevertSelector(ERR_NOT_AGENT);
        _mintGatedQuote(recipient);
    }

    function testFuzzMintCallerNonAgentReverts(address caller) public {
        vm.assume(caller != address(this) && caller != AGENT);
        vm.prank(caller);
        expectRevertSelector(ERR_NOT_AGENT);
        _mintGatedQuote(AGENT);
    }

    function testFuzzMintAgentAmounts(uint96 amount0, uint96 amount1) public {
        vm.assume(amount0 > 1e6 && amount1 > 1e6);
        uint256 tokenId = _mint(gq0, gq1, AGENT, amount0, amount1);
        assertEq(npm.ownerOf(tokenId), AGENT);
        assertTrue(_positionLiquidity(tokenId) > 0);
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _deployNpm(address assetRegistry_) private returns (address payable) {
        return payable(vm.deployCode(
                "AgentswapPositionManager.sol:AgentswapPositionManager",
                abi.encode(factory, address(0xBEEF), address(0), assetRegistry_)
            ));
    }

    /// @dev CREATE the NPM with raw creation code, so the solc 0.7.6 test file
    /// does not need a deploy helper that inherits an ABIEncoderV2 contract.
    function _createNpm(address assetRegistry_) private returns (address deployed) {
        bytes memory creationCode = abi.encodePacked(
            vm.getCode("AgentswapPositionManager.sol:AgentswapPositionManager"),
            abi.encode(factory, address(0xBEEF), address(0), assetRegistry_)
        );
        assembly {
            deployed := create(0, add(creationCode, 0x20), mload(creationCode))
        }
    }

    function _configurePolicy(MockTransferPolicy policy) private {
        policy.setMember(address(this), true);
        policy.setMember(AGENT, true);
        policy.setMember(address(npm), true);
        policy.setCategory(address(npm), CAT_LP_MANAGER);
        policy.setMember(FACILITY, true);
        policy.setCategory(FACILITY, CAT_CUSTODY);
        policy.setMember(FACILITY_POOL, true);
        policy.setCategory(FACILITY_POOL, CAT_POOL);
    }

    function _etchPool(address token0, address token1) private returns (address pool) {
        pool = PoolAddress.computeAddress(factory, PoolAddress.PoolKey({token0: token0, token1: token1, fee: FEE}));
        vm.etch(pool, vm.getDeployedCode("MockV3Pool.sol:MockV3Pool"));
    }

    function _prank(address caller) private {
        if (caller != address(this)) vm.prank(caller);
    }

    function _sort(address tokenA, address tokenB) private pure returns (address token0, address token1) {
        if (tokenA < tokenB) return (tokenA, tokenB);
        return (tokenB, tokenA);
    }

    function _mint(address token0, address token1, address recipient, uint256 amount0, uint256 amount1)
        private
        returns (uint256 tokenId)
    {
        (tokenId,,,) = npm.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: FEE,
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: recipient,
                deadline: uint256(-1)
            })
        );
    }

    function _mintGatedQuote(address recipient) private returns (uint256) {
        return _mint(gq0, gq1, recipient, MINT_AMOUNT, MINT_AMOUNT);
    }

    function _mintGatedGated(address recipient) private returns (uint256) {
        return _mint(gg0, gg1, recipient, MINT_AMOUNT, MINT_AMOUNT);
    }

    function _mintPublic(address recipient) private returns (uint256) {
        return _mint(pp0, pp1, recipient, MINT_AMOUNT, MINT_AMOUNT);
    }

    function _increase(uint256 tokenId, address caller, uint256 amount0, uint256 amount1) private {
        _prank(caller);
        npm.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: uint256(-1)
            })
        );
    }

    function _decrease(uint256 tokenId, address caller, uint128 liquidity)
        private
        returns (uint256 amount0, uint256 amount1)
    {
        _prank(caller);
        return npm.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId, liquidity: liquidity, amount0Min: 0, amount1Min: 0, deadline: uint256(-1)
            })
        );
    }

    function _collect(uint256 tokenId, address caller, address recipient)
        private
        returns (uint256 amount0, uint256 amount1)
    {
        _prank(caller);
        return npm.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId, recipient: recipient, amount0Max: uint128(-1), amount1Max: uint128(-1)
            })
        );
    }

    function _clearPosition(uint256 tokenId, address owner) private {
        _decrease(tokenId, owner, _positionLiquidity(tokenId));
        _collect(tokenId, owner, owner);
    }

    function _positionLiquidity(uint256 tokenId) private view returns (uint128 liquidity) {
        (,,,,,,, liquidity,,,,) = npm.positions(tokenId);
    }

    function _tokensOwed(uint256 tokenId) private view returns (uint128 owed0, uint128 owed1) {
        (,,,,,,,,,, owed0, owed1) = npm.positions(tokenId);
    }

    function _positionExists(uint256 tokenId) private view returns (bool exists) {
        (bool ok,) = address(npm).staticcall(abi.encodeWithSignature("ownerOf(uint256)", tokenId));
        exists = ok;
    }
}
