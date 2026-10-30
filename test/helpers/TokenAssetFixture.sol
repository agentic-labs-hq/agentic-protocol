// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GAME, POOL, VAULT} from "../../contracts/common/Types.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";
import {AgenticTokenFactory} from "../../contracts/token/AgenticTokenFactory.sol";
import {AgenticAssetRegistry} from "../../contracts/registry/AgenticAssetRegistry.sol";
import {AgenticPolicyRegistry} from "../../contracts/policy/AgenticPolicyRegistry.sol";
import {AgenticQuoteAssetRegistry} from "../../contracts/registry/AgenticQuoteAssetRegistry.sol";

import {MockAssetRegistrar} from "../mocks/MockAgentAsset.sol";
import {MockFacility} from "../mocks/MockFacility.sol";
import {MockGatedPool} from "../mocks/MockGatedPool.sol";
import {PolicyVenueFixture} from "./PolicyVenueFixture.sol";

/// @notice fixture: the real venue policy/venue stack plus the policy,
/// asset and quote registries and the token factory wired together.
abstract contract TokenAssetFixture is PolicyVenueFixture {
    AgenticPolicyRegistry internal policyRegistry;
    AgenticAssetRegistry internal assetRegistry;
    AgenticTokenFactory internal factory;
    AgenticQuoteAssetRegistry internal quoteRegistry;
    MockAssetRegistrar internal assetRegistrar;

    MockFacility internal vault2;
    MockFacility internal vault3;
    MockFacility internal game2;
    address internal agent3 = address(0xA113);

    uint256 internal constant MAX_RECIPIENTS = 8;
    uint256 internal constant MAX_POOLS = 4;
    uint256 internal constant MAX_QUOTE_ASSETS = 8;

    string internal constant DEFAULT_NAME = "Agent Token";
    string internal constant DEFAULT_SYMBOL = "AGT";
    string internal constant DEFAULT_URI = "ipfs://agent-token/metadata.json";

    function _deployTokenAsset() internal {
        _deployPolicyVenue();

        // Extra CUSTODY/PURPOSE facilities so fuzz tests have eight distinct
        // eligible recipients (three agents and five facilities).
        vault2 = _createFacility(VAULT, projectOwner);
        vault3 = _createFacility(VAULT, projectOwner);
        game2 = _createFacility(GAME, projectOwner);
        identityAdapter.setHasIdentity(agent3, true);

        policyRegistry = new AgenticPolicyRegistry(address(this), 8);
        policyRegistry.addPolicy(address(policy), 1);
        policyRegistry.setCurrentPolicy(address(policy));

        assetRegistry = new AgenticAssetRegistry(address(this), address(policyRegistry), address(venue), MAX_POOLS);
        factory =
            new AgenticTokenFactory(address(policyRegistry), address(assetRegistry), address(venue), MAX_RECIPIENTS);
        assetRegistry.setRegistrar(address(factory), true);

        quoteRegistry =
            new AgenticQuoteAssetRegistry(address(this), address(assetRegistry), MAX_QUOTE_ASSETS, new address[](0));

        assetRegistrar = new MockAssetRegistrar();
    }

    /// @dev Eight distinct addresses that pass the factory recipient matrix.
    function _eligibleRecipients() internal view returns (address[] memory recipients) {
        recipients = new address[](8);
        recipients[0] = agent;
        recipients[1] = agent2;
        recipients[2] = agent3;
        recipients[3] = address(vault);
        recipients[4] = address(vault2);
        recipients[5] = address(vault3);
        recipients[6] = address(game);
        recipients[7] = address(game2);
    }

    function _createToken(
        address caller,
        address policy_,
        address[] memory recipients,
        uint256[] memory amounts,
        string memory metadataURI_
    ) internal returns (address token) {
        vm.prank(caller);
        token = factory.createToken(DEFAULT_NAME, DEFAULT_SYMBOL, policy_, recipients, amounts, metadataURI_);
    }

    function _createTokenFor(address caller, address recipient, uint256 amount) internal returns (address token) {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = recipient;
        amounts[0] = amount;
        token = _createToken(caller, address(0), recipients, amounts, DEFAULT_URI);
    }

    /// @dev A default factory-created token owned by the agent identity, already
    /// registered as a gated asset.
    function _createRegisteredToken() internal returns (AgenticToken token) {
        token = AgenticToken(_createTokenFor(agent, agent, 1_000 ether));
    }

    function _registerPool(MockGatedPool pool) internal {
        venue.registerFacility(address(pool), POOL);
    }
}
