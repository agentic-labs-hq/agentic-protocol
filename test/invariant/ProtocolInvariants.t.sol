// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {AgenticToken} from "../../contracts/token/AgenticToken.sol";
import {AgenticVaultFacility} from "../../contracts/facility/AgenticVaultFacility.sol";
import {AgenticGameFacility} from "../../contracts/facility/AgenticGameFacility.sol";
import {IntegrationFixture} from "../integration/IntegrationFixture.sol";

/// @notice Stateful handler for the protocol invariants.
contract ProtocolHandler is Test {
    AgenticToken public token;
    AgenticVaultFacility public vault;
    AgenticGameFacility public game;
    address public agent;
    address public agent2;
    address public project;

    function configure(
        AgenticToken token_,
        AgenticVaultFacility vault_,
        AgenticGameFacility game_,
        address agent_,
        address agent2_,
        address project_
    ) external {
        token = token_;
        vault = vault_;
        game = game_;
        agent = agent_;
        agent2 = agent2_;
        project = project_;
    }

    function transferAgent(uint256 amount) external {
        amount = bound(amount, 0, token.balanceOf(agent));
        vm.prank(agent);
        try token.transfer(agent2, amount) returns (bool) {} catch {}
    }

    function transferToGame(uint256 amount) external {
        amount = bound(amount, 0, token.balanceOf(agent));
        vm.prank(agent);
        try token.transfer(address(game), amount) returns (bool) {} catch {}
    }

    function releaseVault(uint256 amount) external {
        amount = bound(amount, 0, token.balanceOf(address(vault)));
        try vault.release(address(token), agent, amount) {} catch {}
    }

    function consumeGame(uint256 amount) external {
        amount = bound(amount, 0, token.balanceOf(address(game)));
        try game.consume(address(token), amount) {} catch {}
    }
}

/// @notice invariants over random agent transfers, vault releases and game consumption.
contract ProtocolInvariantsTest is IntegrationFixture {
    AgenticToken internal token;
    AgenticVaultFacility internal invariantVault;
    AgenticGameFacility internal invariantGame;
    ProtocolHandler internal handler;
    uint256 internal initialSupply;

    function setUp() public override {
        super.setUp();
        handler = new ProtocolHandler();
        invariantVault = _createVault(address(handler));
        invariantGame = _createGame(address(handler), address(handler));

        address[] memory recipients = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        recipients[0] = agent;
        recipients[1] = address(invariantVault);
        recipients[2] = address(invariantGame);
        amounts[0] = 1_000 ether;
        amounts[1] = 500 ether;
        amounts[2] = 500 ether;
        token = _createToken(recipients, amounts);
        initialSupply = token.totalSupply();

        handler.configure(token, invariantVault, invariantGame, agent, agent2, projectOwner);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = ProtocolHandler.transferAgent.selector;
        selectors[1] = ProtocolHandler.transferToGame.selector;
        selectors[2] = ProtocolHandler.releaseVault.selector;
        selectors[3] = ProtocolHandler.consumeGame.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_totalSupplyConstant() public view {
        assertEq(token.totalSupply(), initialSupply);
    }

    function invariant_nonAgentNeverHoldsGated() public view {
        assertEq(token.balanceOf(projectOwner), 0);
        assertEq(token.balanceOf(nonAgent), 0);
    }
}
