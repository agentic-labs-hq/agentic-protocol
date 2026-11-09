// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgenticNFT} from "../../contracts/token/AgenticNFT.sol";
import {AgenticNFTFactory} from "../../contracts/token/AgenticNFTFactory.sol";
import {AgenticNFTRegistry} from "../../contracts/registry/AgenticNFTRegistry.sol";
import {AgenticPolicyRegistry} from "../../contracts/policy/AgenticPolicyRegistry.sol";

import {MockNFTRegistrar} from "../mocks/MockAgentNFT.sol";
import {PolicyVenueFixture} from "./PolicyVenueFixture.sol";

/// @notice NFT fixture: the real policy/venue stack plus the NFT policy
/// registry, NFT registry and NFT factory wired together.
abstract contract NFTAssetFixture is PolicyVenueFixture {
    AgenticPolicyRegistry internal policyRegistry;
    AgenticNFTRegistry internal nftRegistry;
    AgenticNFTFactory internal nftFactory;
    MockNFTRegistrar internal nftRegistrar;

    uint256 internal constant MAX_POLICIES = 8;
    uint256 internal constant DEFAULT_MAX_SUPPLY = 10_000;

    string internal constant DEFAULT_NAME = "Agent NFT";
    string internal constant DEFAULT_SYMBOL = "AGNFT";
    string internal constant DEFAULT_BASE_URI = "ipfs://agent-nft/";
    string internal constant DEFAULT_METADATA_URI = "ipfs://agent-nft/collection.json";

    function _deployNFTAsset() internal {
        _deployPolicyVenue();

        policyRegistry = new AgenticPolicyRegistry(address(this), MAX_POLICIES);
        policyRegistry.addPolicy(address(policy), 1);
        policyRegistry.setCurrentPolicy(address(policy));

        nftRegistry = new AgenticNFTRegistry(address(this), address(policyRegistry));
        nftFactory = new AgenticNFTFactory(address(policyRegistry), address(nftRegistry));
        nftRegistry.setRegistrar(address(nftFactory), true);

        nftRegistrar = new MockNFTRegistrar();
    }

    function _createCollection(address caller, address policy_, uint256 maxSupply_, address metadataResolver_)
        internal
        returns (AgenticNFT nft)
    {
        vm.prank(caller);
        nft = AgenticNFT(
            nftFactory.createCollection(
                DEFAULT_NAME,
                DEFAULT_SYMBOL,
                policy_,
                maxSupply_,
                DEFAULT_BASE_URI,
                DEFAULT_METADATA_URI,
                metadataResolver_
            )
        );
    }

    /// @dev A default factory-created collection owned by the agent identity,
    /// already registered as a gated NFT.
    function _createRegisteredCollection() internal returns (AgenticNFT nft) {
        nft = _createCollection(agent, address(0), DEFAULT_MAX_SUPPLY, address(0));
    }
}
