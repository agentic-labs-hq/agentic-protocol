// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Governance2Step} from "../../contracts/common/Governance2Step.sol";
import {AgenticQuoteAssetRegistry} from "../../contracts/registry/AgenticQuoteAssetRegistry.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";

import {MockERC20, MockERC20NoBalanceOf, MockERC20RevertingTotalSupply} from "../mocks/MockERC20.sol";
import {MockVenueAccount} from "../mocks/MockVenueAccount.sol";
import {TokenAssetFixture} from "../helpers/TokenAssetFixture.sol";

contract AgenticQuoteAssetRegistryTest is TokenAssetFixture {
    event QuoteAssetAdded(address indexed token);
    event QuoteAssetRemoved(address indexed token);

    AgenticQuoteAssetRegistry internal registry;
    MockERC20 internal wbnb;
    MockERC20 internal usdt;

    function setUp() public {
        _deployTokenAsset();
        registry = quoteRegistry;
        wbnb = new MockERC20();
        usdt = new MockERC20();
    }

    // ---------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------

    function testInitialState() public view {
        assertEq(registry.governance(), address(this));
        assertEq(registry.pendingGovernance(), address(0));
        assertEq(registry.assetRegistry(), address(assetRegistry));
        assertEq(registry.maxQuoteAssets(), MAX_QUOTE_ASSETS);
        assertEq(registry.quoteAssets().length, 0);
        assertFalse(registry.isQuoteAsset(address(wbnb)));
    }

    function testConstructorRejectsZeroAssetRegistry() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticQuoteAssetRegistry.InvalidAssetRegistry.selector, address(0)));
        new AgenticQuoteAssetRegistry(address(this), address(0), MAX_QUOTE_ASSETS, new address[](0));
    }

    function testConstructorRejectsCodelessAssetRegistry() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticQuoteAssetRegistry.InvalidAssetRegistry.selector, nonAgent));
        new AgenticQuoteAssetRegistry(address(this), nonAgent, MAX_QUOTE_ASSETS, new address[](0));
    }

    function testConstructorRejectsZeroCap() public {
        vm.expectRevert(AgenticQuoteAssetRegistry.InvalidMaxQuoteAssets.selector);
        new AgenticQuoteAssetRegistry(address(this), address(assetRegistry), 0, new address[](0));
    }

    function testConstructorAddsInitialList() public {
        address[] memory initial = new address[](2);
        initial[0] = address(wbnb);
        initial[1] = address(usdt);

        AgenticQuoteAssetRegistry seeded =
            new AgenticQuoteAssetRegistry(address(this), address(assetRegistry), 2, initial);

        address[] memory listed = seeded.quoteAssets();
        assertEq(listed.length, 2);
        assertEq(listed[0], address(wbnb));
        assertEq(listed[1], address(usdt));
        assertTrue(seeded.isQuoteAsset(address(wbnb)));
        assertTrue(seeded.isQuoteAsset(address(usdt)));
    }

    function testConstructorRejectsGatedInitialAsset() public {
        AgenticToken token = _createRegisteredToken();
        address[] memory initial = new address[](1);
        initial[0] = address(token);

        vm.expectRevert(abi.encodeWithSelector(AgenticQuoteAssetRegistry.GatedAssetNotAllowed.selector, address(token)));
        new AgenticQuoteAssetRegistry(address(this), address(assetRegistry), MAX_QUOTE_ASSETS, initial);
    }

    function testConstructorEnforcesCap() public {
        address[] memory initial = new address[](2);
        initial[0] = address(wbnb);
        initial[1] = address(usdt);

        vm.expectRevert(abi.encodeWithSelector(AgenticQuoteAssetRegistry.QuoteCapReached.selector, 1));
        new AgenticQuoteAssetRegistry(address(this), address(assetRegistry), 1, initial);
    }

    // ---------------------------------------------------------------------
    // addQuoteAsset
    // ---------------------------------------------------------------------

    function testAddQuoteAsset() public {
        vm.expectEmit(true, false, false, true, address(registry));
        emit QuoteAssetAdded(address(wbnb));
        registry.addQuoteAsset(address(wbnb));

        assertTrue(registry.isQuoteAsset(address(wbnb)));
        address[] memory listed = registry.quoteAssets();
        assertEq(listed.length, 1);
        assertEq(listed[0], address(wbnb));
    }

    function testAddQuoteAssetOnlyGovernance() public {
        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonAgent));
        registry.addQuoteAsset(address(wbnb));
    }

    function testAddZeroTokenRejected() public {
        vm.expectRevert(AgenticQuoteAssetRegistry.ZeroToken.selector);
        registry.addQuoteAsset(address(0));
    }

    function testAddCodelessTokenRejected() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticQuoteAssetRegistry.TokenHasNoCode.selector, nonAgent));
        registry.addQuoteAsset(nonAgent);
    }

    function testAddDuplicateRejected() public {
        registry.addQuoteAsset(address(wbnb));

        vm.expectRevert(
            abi.encodeWithSelector(AgenticQuoteAssetRegistry.QuoteAssetAlreadyAdded.selector, address(wbnb))
        );
        registry.addQuoteAsset(address(wbnb));
    }

    function testAddGatedAssetRejected() public {
        AgenticToken token = _createRegisteredToken();

        vm.expectRevert(abi.encodeWithSelector(AgenticQuoteAssetRegistry.GatedAssetNotAllowed.selector, address(token)));
        registry.addQuoteAsset(address(token));
    }

    function testAddNonERC20Rejected() public {
        MockVenueAccount notToken = new MockVenueAccount();
        vm.expectRevert(abi.encodeWithSelector(AgenticQuoteAssetRegistry.NotERC20.selector, address(notToken)));
        registry.addQuoteAsset(address(notToken));

        MockERC20NoBalanceOf noBalanceOf = new MockERC20NoBalanceOf();
        vm.expectRevert(abi.encodeWithSelector(AgenticQuoteAssetRegistry.NotERC20.selector, address(noBalanceOf)));
        registry.addQuoteAsset(address(noBalanceOf));

        MockERC20RevertingTotalSupply reverting = new MockERC20RevertingTotalSupply();
        vm.expectRevert(abi.encodeWithSelector(AgenticQuoteAssetRegistry.NotERC20.selector, address(reverting)));
        registry.addQuoteAsset(address(reverting));
    }

    function testAddRespectsCap() public {
        AgenticQuoteAssetRegistry capped = _newRegistry(2, new address[](0));
        MockERC20 third = new MockERC20();
        capped.addQuoteAsset(address(wbnb));
        capped.addQuoteAsset(address(usdt));

        vm.expectRevert(abi.encodeWithSelector(AgenticQuoteAssetRegistry.QuoteCapReached.selector, 2));
        capped.addQuoteAsset(address(third));
    }

    // ---------------------------------------------------------------------
    // removeQuoteAsset
    // ---------------------------------------------------------------------

    function testRemoveQuoteAsset() public {
        registry.addQuoteAsset(address(wbnb));
        registry.addQuoteAsset(address(usdt));

        vm.expectEmit(true, false, false, true, address(registry));
        emit QuoteAssetRemoved(address(wbnb));
        registry.removeQuoteAsset(address(wbnb));

        assertFalse(registry.isQuoteAsset(address(wbnb)));
        address[] memory listed = registry.quoteAssets();
        assertEq(listed.length, 1);
        assertEq(listed[0], address(usdt));
    }

    function testRemoveOnlyGovernance() public {
        registry.addQuoteAsset(address(wbnb));

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonAgent));
        registry.removeQuoteAsset(address(wbnb));
    }

    function testRemoveNotListedRejected() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticQuoteAssetRegistry.QuoteAssetNotListed.selector, address(wbnb)));
        registry.removeQuoteAsset(address(wbnb));
    }

    function testSwapRemoveKeepsListConsistent() public {
        MockERC20 third = new MockERC20();
        registry.addQuoteAsset(address(wbnb));
        registry.addQuoteAsset(address(usdt));
        registry.addQuoteAsset(address(third));

        // Remove the middle entry: the last entry is swapped into its slot.
        registry.removeQuoteAsset(address(usdt));

        address[] memory listed = registry.quoteAssets();
        assertEq(listed.length, 2);
        assertEq(listed[0], address(wbnb));
        assertEq(listed[1], address(third));

        registry.removeQuoteAsset(address(third));
        listed = registry.quoteAssets();
        assertEq(listed.length, 1);
        assertEq(listed[0], address(wbnb));

        // Re-adding after removal works and restores a valid index.
        registry.addQuoteAsset(address(usdt));
        listed = registry.quoteAssets();
        assertEq(listed.length, 2);
        assertEq(listed[1], address(usdt));
        assertTrue(registry.isQuoteAsset(address(usdt)));
    }

    function testRemoveLastEntry() public {
        registry.addQuoteAsset(address(wbnb));
        registry.addQuoteAsset(address(usdt));
        registry.removeQuoteAsset(address(usdt));

        address[] memory listed = registry.quoteAssets();
        assertEq(listed.length, 1);
        assertEq(listed[0], address(wbnb));
    }

    // ---------------------------------------------------------------------
    // Governance
    // ---------------------------------------------------------------------

    function testGovernanceTwoStep() public {
        address newGov = address(0xC0FFEE);
        registry.transferGovernance(newGov);
        assertEq(registry.pendingGovernance(), newGov);

        vm.prank(newGov);
        registry.acceptGovernance();
        assertEq(registry.governance(), newGov);

        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, address(this)));
        registry.addQuoteAsset(address(wbnb));

        vm.prank(newGov);
        registry.addQuoteAsset(address(wbnb));
        assertTrue(registry.isQuoteAsset(address(wbnb)));
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _newRegistry(uint256 cap, address[] memory initial) internal returns (AgenticQuoteAssetRegistry) {
        return new AgenticQuoteAssetRegistry(address(this), address(assetRegistry), cap, initial);
    }
}
