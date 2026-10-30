// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgenticAssetRegistry} from "../../contracts/registry/AgenticAssetRegistry.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";
import {AgenticTokenFactory} from "../../contracts/token/AgenticTokenFactory.sol";
import {AgenticQuoteAssetRegistry} from "../../contracts/registry/AgenticQuoteAssetRegistry.sol";
import {FacilityCategory} from "../../contracts/common/Types.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {MockGatedPool} from "../mocks/MockGatedPool.sol";
import {TokenAssetFixture} from "../helpers/TokenAssetFixture.sol";

contract TokenAssetFuzzTest is TokenAssetFixture {
    function setUp() public {
        _deployTokenAsset();
    }

    /// @dev The whole initial supply is minted exactly once to the recipients,
    /// and the factory never retains a balance.
    function testFuzzInitialMintAccounting(uint96 amount0, uint96 amount1) public {
        amount0 = uint96(bound(amount0, 1, type(uint96).max));
        amount1 = uint96(bound(amount1, 1, type(uint96).max));

        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        recipients[0] = agent;
        recipients[1] = address(vault);
        amounts[0] = amount0;
        amounts[1] = amount1;

        address token = _createToken(projectOwner, address(0), recipients, amounts, DEFAULT_URI);

        assertEq(AgenticToken(token).totalSupply(), uint256(amount0) + uint256(amount1));
        assertEq(AgenticToken(token).balanceOf(agent), amount0);
        assertEq(AgenticToken(token).balanceOf(address(vault)), amount1);
        assertEq(AgenticToken(token).balanceOf(address(factory)), 0);
        assertEq(AgenticToken(token).creator(), projectOwner);
        assertTrue(assetRegistry.isRegistered(token));
    }

    /// @dev Recipient count is accepted in `[1, maxRecipients]` and rejected
    /// outside it, regardless of which eligible addresses are used.
    function testFuzzRecipientCountBoundary(uint8 rawCount) public {
        uint256 count = bound(rawCount, 0, 12);
        address[] memory eligible = _eligibleRecipients();
        address[] memory recipients = new address[](count);
        uint256[] memory amounts = new uint256[](count);

        for (uint256 i; i < count; ++i) {
            recipients[i] = i < eligible.length ? eligible[i] : address(uint160(0x100000 + i));
            amounts[i] = 1 ether;
        }

        if (count == 0 || count > MAX_RECIPIENTS) {
            vm.expectRevert(
                abi.encodeWithSelector(AgenticTokenFactory.InvalidRecipientCount.selector, count, MAX_RECIPIENTS)
            );
            _createToken(agent, address(0), recipients, amounts, DEFAULT_URI);
            return;
        }

        address token = _createToken(agent, address(0), recipients, amounts, DEFAULT_URI);
        assertEq(AgenticToken(token).totalSupply(), count * 1 ether);
        for (uint256 i; i < count; ++i) {
            assertEq(AgenticToken(token).balanceOf(recipients[i]), 1 ether);
        }
    }

    /// @dev Every faucet of the recipient category matrix: agents and active
    /// CUSTODY/PURPOSE facilities pass; POOL/LP_MANAGER/FEE_RECIPIENT and
    /// non-agents always revert.
    function testFuzzRecipientCategoryMatrix(uint8 rawCategory) public {
        uint256 category = bound(rawCategory, 0, 7);

        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        if (category == 0) {
            recipients[0] = agent;
            address token = _createToken(agent, address(0), recipients, amounts, DEFAULT_URI);
            assertEq(AgenticToken(token).balanceOf(agent), 1 ether);
        } else if (category == 1) {
            recipients[0] = address(vault);
            address token = _createToken(projectOwner, address(0), recipients, amounts, DEFAULT_URI);
            assertEq(AgenticToken(token).balanceOf(address(vault)), 1 ether);
        } else if (category == 2) {
            recipients[0] = address(game);
            address token = _createToken(projectOwner, address(0), recipients, amounts, DEFAULT_URI);
            assertEq(AgenticToken(token).balanceOf(address(game)), 1 ether);
        } else if (category == 3) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    AgenticTokenFactory.RecipientCategoryNotAllowed.selector, address(pool), FacilityCategory.POOL
                )
            );
            _createToken(agent, address(0), _addresses(address(pool)), amounts, DEFAULT_URI);
        } else if (category == 4) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    AgenticTokenFactory.RecipientCategoryNotAllowed.selector,
                    address(lpManager),
                    FacilityCategory.LP_MANAGER
                )
            );
            _createToken(agent, address(0), _addresses(address(lpManager)), amounts, DEFAULT_URI);
        } else if (category == 5) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    AgenticTokenFactory.RecipientCategoryNotAllowed.selector,
                    address(feeRecipient),
                    FacilityCategory.FEE_RECIPIENT
                )
            );
            _createToken(agent, address(0), _addresses(address(feeRecipient)), amounts, DEFAULT_URI);
        } else {
            vm.expectRevert(abi.encodeWithSelector(AgenticTokenFactory.RecipientNotEligible.selector, nonAgent));
            _createToken(agent, address(0), _addresses(nonAgent), amounts, DEFAULT_URI);
        }
    }

    /// @dev Total supply must be strictly positive, independent of recipient count.
    function testFuzzZeroTotalSupplyRejected(uint8 rawCount) public {
        uint256 count = bound(rawCount, 1, MAX_RECIPIENTS);
        address[] memory eligible = _eligibleRecipients();
        address[] memory recipients = new address[](count);
        uint256[] memory amounts = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            recipients[i] = eligible[i];
        }

        vm.expectRevert(AgenticTokenFactory.ZeroInitialSupply.selector);
        _createToken(agent, address(0), recipients, amounts, DEFAULT_URI);
    }

    /// @dev No arbitrary address can register an asset, regardless of the asset.
    function testFuzzNoRegistrationBypass(address caller, address asset) public {
        vm.assume(caller != address(factory));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(AgenticAssetRegistry.NotRegistrar.selector, caller));
        assetRegistry.registerAsset(asset, address(policy), agent);
    }

    /// @dev Pool records are capped per asset and each distinct pool counts.
    function testFuzzPoolCap(uint8 rawCount) public {
        uint256 count = bound(rawCount, 0, 8);
        AgenticToken token = _createRegisteredToken();
        venue.setRegistrar(address(assetRegistrar), FacilityCategory.POOL, true);

        for (uint256 i; i < count; ++i) {
            MockGatedPool pool = new MockGatedPool(address(token), address(uint160(0x9000 + i)));
            _registerPool(pool);

            if (i < MAX_POOLS) {
                assetRegistrar.record(address(assetRegistry), address(token), address(pool));
            } else {
                vm.expectRevert(abi.encodeWithSelector(AgenticAssetRegistry.PoolCapReached.selector, MAX_POOLS));
                assetRegistrar.record(address(assetRegistry), address(token), address(pool));
            }
        }

        uint256 expected = count < MAX_POOLS ? count : MAX_POOLS;
        assertEq(assetRegistry.poolsOf(address(token)).length, expected);
    }

    /// @dev The quote allowlist cap is exact.
    function testFuzzQuoteCap(uint8 rawCount) public {
        uint256 count = bound(rawCount, 0, 6);
        uint256 cap = 3;
        AgenticQuoteAssetRegistry capped =
            new AgenticQuoteAssetRegistry(address(this), address(assetRegistry), cap, new address[](0));

        for (uint256 i; i < count; ++i) {
            MockERC20 token = new MockERC20();
            if (i < cap) {
                capped.addQuoteAsset(address(token));
            } else {
                vm.expectRevert(abi.encodeWithSelector(AgenticQuoteAssetRegistry.QuoteCapReached.selector, cap));
                capped.addQuoteAsset(address(token));
            }
        }

        uint256 expected = count < cap ? count : cap;
        assertEq(capped.quoteAssets().length, expected);
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _addresses(address value) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = value;
    }
}
