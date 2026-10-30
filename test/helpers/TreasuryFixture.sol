// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {FacilityCategory, TREASURY} from "../../contracts/common/Types.sol";
import {AgenticTreasury} from "../../contracts/treasury/AgenticTreasury.sol";

import {MockAgenticToken} from "../mocks/MockAgenticToken.sol";
import {MockAssetRegistry} from "../mocks/MockAssetRegistry.sol";
import {MockSwapRouter} from "../mocks/MockSwapRouter.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {MockTransferPolicy} from "../mocks/MockTransferPolicy.sol";
import {MockVenueAccount} from "../mocks/MockVenueAccount.sol";
import {MockVenueRegistry} from "../mocks/MockVenueRegistry.sol";

/// @notice Shared treasury fixture: mocks for every external dependency.
/// @dev The treasury itself is deployed with `address(this)` as governance; each
/// test can revoke/replace it in the mock registry without touching venue code.
abstract contract TreasuryFixture is Test {
    uint256 internal constant INITIAL_BALANCE = 1_000_000e18;
    uint256 internal constant MAX_BATCH = 4;
    uint256 internal constant START_TIMESTAMP = 1_000_000;

    AgenticTreasury internal treasury;
    MockAssetRegistry internal assetRegistry;
    MockVenueRegistry internal venueRegistry;
    MockSwapRouter internal router;
    MockTransferPolicy internal policy;
    MockAgenticToken internal gatedToken;
    MockToken internal publicToken;
    MockToken internal publicTokenB;
    MockVenueAccount internal replacement;
    MockVenueAccount internal replacement2;

    address internal agent = address(0xA11CE);
    address internal agent2 = address(0xB0B);
    address internal nonAgent = address(0xBAD);
    address internal nonGov = address(0xCAFE);

    function _deployTreasury() internal {
        vm.warp(START_TIMESTAMP);

        assetRegistry = new MockAssetRegistry();
        venueRegistry = new MockVenueRegistry();
        router = new MockSwapRouter();

        treasury = new AgenticTreasury(
            address(assetRegistry), address(venueRegistry), address(router), MAX_BATCH, address(this)
        );

        policy = new MockTransferPolicy();
        gatedToken = new MockAgenticToken(address(policy));
        publicToken = new MockToken();
        publicTokenB = new MockToken();

        policy.setMember(agent, true);
        policy.setMember(agent2, true);

        assetRegistry.setRegistered(address(gatedToken), true);
        gatedToken.mint(address(treasury), INITIAL_BALANCE);
        publicToken.mint(address(treasury), INITIAL_BALANCE);
        publicTokenB.mint(address(treasury), INITIAL_BALANCE);

        // The treasury is a registered, active FEE_RECIPIENT in the mock registry.
        venueRegistry.setFacilityForTest(address(treasury), FacilityCategory.FEE_RECIPIENT, TREASURY, true);

        replacement = new MockVenueAccount();
        replacement2 = new MockVenueAccount();
        venueRegistry.setFacilityForTest(address(replacement), FacilityCategory.FEE_RECIPIENT, TREASURY, true);
        venueRegistry.setFacilityForTest(address(replacement2), FacilityCategory.FEE_RECIPIENT, TREASURY, true);
    }

    function _revokeTreasury() internal {
        venueRegistry.setRevokedForTest(address(treasury), true);
    }

    function _setTreasuryReplacement(address replacement_) internal {
        venueRegistry.setReplacementForTest(address(treasury), replacement_);
    }

    /// @dev All registry prerequisites for `migrate`, except the `migrate` call.
    function _prepareMigration(address replacement_) internal {
        _revokeTreasury();
        _setTreasuryReplacement(replacement_);
    }

    function _fundNative() internal {
        vm.deal(address(treasury), INITIAL_BALANCE);
    }

    function _deadline() internal view returns (uint256) {
        return block.timestamp + 1 hours;
    }
}
