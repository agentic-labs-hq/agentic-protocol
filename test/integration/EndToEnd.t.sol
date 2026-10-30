// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgenticToken} from "../../contracts/token/AgenticToken.sol";
import {AgenticTreasury} from "../../contracts/treasury/AgenticTreasury.sol";
import {AgenticVaultFacility} from "../../contracts/facility/AgenticVaultFacility.sol";
import {AgenticGameFacility} from "../../contracts/facility/AgenticGameFacility.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {IntegrationFixture} from "./IntegrationFixture.sol";

/// @notice end-to-end: real identity/policy/venue/asset/token/facility/treasury.
contract EndToEndTest is IntegrationFixture {
    function testAgentFacilityMatrixAndPublicAsset() public {
        address[] memory recipients = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        recipients[0] = agent;
        recipients[1] = address(vault);
        recipients[2] = address(game);
        amounts[0] = 1_000 ether;
        amounts[1] = 500 ether;
        amounts[2] = 500 ether;
        AgenticToken token = _createToken(recipients, amounts);

        assertEq(token.totalSupply(), 2_000 ether);
        assertEq(token.balanceOf(agent), 1_000 ether);
        assertEq(token.balanceOf(address(vault)), 500 ether);
        assertEq(token.balanceOf(address(game)), 500 ether);

        // Agent <-> Agent.
        vm.prank(agent);
        token.transfer(agent2, 10 ether);
        assertEq(token.balanceOf(agent2), 10 ether);

        // Agent -> CUSTODY denied; CUSTODY -> Agent allowed.
        vm.prank(agent);
        vm.expectRevert();
        token.transfer(address(vault), 1 ether);

        vault.release(address(token), agent, 100 ether);
        assertEq(token.balanceOf(agent), 1_090 ether);

        // Gated non-agent recipient denied.
        vm.expectRevert();
        vault.release(address(token), projectOwner, 1 ether);

        // Agent -> PURPOSE allowed; PURPOSE -> Agent allowed; consume locks.
        vm.prank(agent);
        token.transfer(address(game), 10 ether);
        game.release(address(token), agent, 20 ether);
        uint256 gameBalanceBefore = token.balanceOf(address(game));
        game.consume(address(token), 100 ether);
        assertEq(token.balanceOf(address(game)), gameBalanceBefore);
        assertEq(game.availableOf(address(token)), gameBalanceBefore - 100 ether);

        // Public ERC20 in VAULT: owner may release to a non-agent; gated path is unchanged.
        MockToken publicToken = new MockToken();
        publicToken.mint(address(vault), 100 ether);
        vault.release(address(publicToken), projectOwner, 100 ether);
        assertEq(publicToken.balanceOf(projectOwner), 100 ether);
    }

    function testFacilityMigrationNonAtomic() public {
        AgenticVaultFacility vault1 = _createVault(address(this));
        AgenticVaultFacility vault2 = _createVault(address(this));
        AgenticToken token = _createTokenFor(address(vault1), 100 ether);

        venue.revokeFacility(address(vault1));
        venue.setReplacement(address(vault1), address(vault2));
        vault1.migrate(address(vault2));
        vault1.release(address(token), address(vault2), 100 ether);

        assertEq(token.balanceOf(address(vault2)), 100 ether);
        vm.expectRevert();
        vault1.release(address(token), agent, 1 ether);
    }

    function testTreasuryGatedFeeAndMigration() public {
        AgenticToken token = _createTokenFor(agent, 1_000 ether);
        _fundPoolWithGated(token, 100 ether);
        assertEq(token.balanceOf(address(treasury)), 100 ether);

        MockToken publicToken = new MockToken();
        vm.expectRevert(AgenticTreasury.GatedSwapNotAllowed.selector);
        treasury.swapExactInputSingle(address(token), address(publicToken), 3_000, 1 ether, 0, block.timestamp);

        treasury.transferToken(address(token), agent, 40 ether);
        assertEq(token.balanceOf(address(treasury)), 60 ether);

        venue.revokeFacility(address(treasury));
        venue.setReplacement(address(treasury), address(feeReplacement));
        treasury.migrate(address(feeReplacement));
        treasury.transferToken(address(token), address(feeReplacement), 60 ether);

        assertEq(token.balanceOf(address(treasury)), 0);
        assertEq(token.balanceOf(address(feeReplacement)), 60 ether);
    }
}
