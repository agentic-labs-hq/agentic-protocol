// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    FacilityCategory,
    NFT_ESCROW,
    NFT_GAME,
    NFT_LAUNCH,
    NFT_LOCKER,
    NFT_VAULT
} from "../../contracts/common/Types.sol";
import {AgenticNFTFacilityFactory} from "../../contracts/facility/AgenticNFTFacilityFactory.sol";
import {AgenticNFTEscrowFacility} from "../../contracts/facility/AgenticNFTEscrowFacility.sol";
import {AgenticNFTGameFacility} from "../../contracts/facility/AgenticNFTGameFacility.sol";
import {AgenticNFTLaunchFacility} from "../../contracts/facility/AgenticNFTLaunchFacility.sol";
import {AgenticNFTLockerFacility} from "../../contracts/facility/AgenticNFTLockerFacility.sol";
import {AgenticNFTVaultFacility} from "../../contracts/facility/AgenticNFTVaultFacility.sol";
import {IFacility} from "../../contracts/interfaces/IFacility.sol";
import {AgenticNFT} from "../../contracts/token/AgenticNFT.sol";

import {MockNFTRegistry} from "../mocks/MockNFTRegistry.sol";
import {PolicyVenueFixture} from "./PolicyVenueFixture.sol";

/// @notice NFT facility fixture: the real policy/venue stack, the real NFT
/// facility factory plus its five template helpers, a mock NFT registry and a
/// helper that deploys real `AgenticNFT` collections.
abstract contract NFTFacilityFixture is PolicyVenueFixture {
    AgenticNFTFacilityFactory internal nftFacilities;
    MockNFTRegistry internal nftRegistry;
    MockNFTFactory internal nftFactory;

    uint64 internal constant DEFAULT_UNLOCK_TIME = 2_000_000_000;
    uint256 internal constant DEFAULT_MAX_SUPPLY = 1_000;

    string internal constant NFT_NAME = "Agent NFT";
    string internal constant NFT_SYMBOL = "ANFT";
    string internal constant NFT_BASE_URI = "ipfs://agent-nft/";
    string internal constant NFT_METADATA_URI = "ipfs://agent-nft/collection.json";

    /// @dev Deploy the standard NFT facility factory, map the five NFT subtypes
    /// and make the factory the CUSTODY/PURPOSE registrar.
    function _deployNFTFacilities() internal {
        _deployPolicyVenue();

        venue.addTypeCategory(NFT_VAULT, FacilityCategory.CUSTODY);
        venue.addTypeCategory(NFT_LAUNCH, FacilityCategory.CUSTODY);
        venue.addTypeCategory(NFT_LOCKER, FacilityCategory.CUSTODY);
        venue.addTypeCategory(NFT_GAME, FacilityCategory.PURPOSE);
        venue.addTypeCategory(NFT_ESCROW, FacilityCategory.PURPOSE);

        nftRegistry = new MockNFTRegistry();
        nftFactory = new MockNFTFactory();

        AgenticNFTFacilityFactory.TemplateDeployers memory deployers = AgenticNFTFacilityFactory.TemplateDeployers({
            vault: vm.deployCode("AgenticNFTFacilityFactory.sol:AgenticNFTVaultTemplateDeployer"),
            launch: vm.deployCode("AgenticNFTFacilityFactory.sol:AgenticNFTLaunchTemplateDeployer"),
            locker: vm.deployCode("AgenticNFTFacilityFactory.sol:AgenticNFTLockerTemplateDeployer"),
            game: vm.deployCode("AgenticNFTFacilityFactory.sol:AgenticNFTGameTemplateDeployer"),
            escrow: vm.deployCode("AgenticNFTFacilityFactory.sol:AgenticNFTEscrowTemplateDeployer")
        });
        nftFacilities = AgenticNFTFacilityFactory(
            vm.deployCode(
                "AgenticNFTFacilityFactory.sol:AgenticNFTFacilityFactory",
                abi.encode(address(policy), address(venue), address(nftRegistry), deployers)
            )
        );

        venue.setRegistrar(address(nftFacilities), FacilityCategory.CUSTODY, true);
        venue.setRegistrar(address(nftFacilities), FacilityCategory.PURPOSE, true);
    }

    // ------------------------------------------------------------- collections

    /// @dev Deploy a real `AgenticNFT` with the canonical policy and register it
    /// as a gated collection. `agent` is the creator and sole minter.
    function _createNFTCollection() internal returns (AgenticNFT nft) {
        nft = _createNFTCollectionWithPolicy(address(policy), true);
    }

    /// @dev Deploy a collection with a custom policy; `registered` controls the
    /// gated classification in `MockNFTRegistry`.
    function _createNFTCollectionWithPolicy(address policy_, bool registered) internal returns (AgenticNFT nft) {
        nft = nftFactory.createCollection(
            NFT_NAME, NFT_SYMBOL, policy_, agent, DEFAULT_MAX_SUPPLY, NFT_BASE_URI, NFT_METADATA_URI, address(0)
        );
        if (registered) nftRegistry.setRegistered(address(nft), true);
    }

    /// @dev Mint one token to `to`; returns the new token id (ids start at 0).
    function _mintNFT(AgenticNFT nft, address to) internal returns (uint256 tokenId) {
        tokenId = nft.totalMinted();
        vm.prank(nft.creator());
        nft.mint(to, 1);
    }

    /// @dev Mint `count` consecutive tokens to `to`; returns the first token id.
    function _mintNFTCount(AgenticNFT nft, address to, uint256 count) internal returns (uint256 firstTokenId) {
        firstTokenId = nft.totalMinted();
        vm.prank(nft.creator());
        nft.mint(to, count);
    }

    /// @dev Agent deposits one held token into a PURPOSE facility. CUSTODY
    /// facilities are funded by mint only (the policy denies agent -> CUSTODY).
    function _depositNFT(AgenticNFT nft, address facility, uint256 tokenId) internal {
        vm.prank(agent);
        nft.safeTransferFrom(agent, facility, tokenId);
    }

    // ---------------------------------------------------------------- factory

    function _createNFTVault(address owner_) internal returns (AgenticNFTVaultFacility facility) {
        facility = AgenticNFTVaultFacility(nftFacilities.createFacility(NFT_VAULT, abi.encode(owner_)));
    }

    function _createNFTLaunch(address owner_, address operator_, address beneficiary_)
        internal
        returns (AgenticNFTLaunchFacility facility)
    {
        facility = AgenticNFTLaunchFacility(
            nftFacilities.createFacility(NFT_LAUNCH, abi.encode(owner_, operator_, beneficiary_))
        );
    }

    function _createNFTLocker(address owner_, address beneficiary_, uint64 unlockTime_)
        internal
        returns (AgenticNFTLockerFacility facility)
    {
        facility = AgenticNFTLockerFacility(
            nftFacilities.createFacility(NFT_LOCKER, abi.encode(owner_, beneficiary_, unlockTime_))
        );
    }

    function _createNFTGame(address owner_, address operator_) internal returns (AgenticNFTGameFacility facility) {
        facility = AgenticNFTGameFacility(nftFacilities.createFacility(NFT_GAME, abi.encode(owner_, operator_)));
    }

    function _createNFTEscrow(address owner_, address arbiter_, address beneficiary_)
        internal
        returns (AgenticNFTEscrowFacility facility)
    {
        facility = AgenticNFTEscrowFacility(
            nftFacilities.createFacility(NFT_ESCROW, abi.encode(owner_, arbiter_, beneficiary_))
        );
    }

    function _defaultNFTVault() internal returns (AgenticNFTVaultFacility) {
        return _createNFTVault(projectOwner);
    }

    function _defaultNFTLaunch() internal returns (AgenticNFTLaunchFacility) {
        return _createNFTLaunch(projectOwner, projectOwner, agent);
    }

    function _defaultNFTLocker() internal returns (AgenticNFTLockerFacility) {
        return _createNFTLocker(projectOwner, agent, DEFAULT_UNLOCK_TIME);
    }

    function _defaultNFTGame() internal returns (AgenticNFTGameFacility) {
        return _createNFTGame(projectOwner, projectOwner);
    }

    function _defaultNFTEscrow() internal returns (AgenticNFTEscrowFacility) {
        return _createNFTEscrow(projectOwner, projectOwner, agent);
    }

    // -------------------------------------------------------------- migration

    /// @dev The registry replacement must be set by the facility owner itself.
    function _setNFTReplacement(address facility, address replacement) internal {
        vm.prank(IFacility(facility).owner());
        venue.setReplacement(facility, replacement);
    }

    function _revokeNFTFacility(address facility) internal {
        venue.revokeFacility(facility);
    }

    function _migrateNFTFacility(address facility, address replacement) internal {
        vm.prank(IFacility(facility).owner());
        IFacilityMigrate(facility).migrate(replacement);
    }
}

/// @dev Small helper that deploys real `AgenticNFT` collections. `AgenticNFT`
/// requires `msg.sender == factory_`, so the test cannot `new` it directly.
contract MockNFTFactory {
    function createCollection(
        string memory name_,
        string memory symbol_,
        address policy_,
        address creator_,
        uint256 maxSupply_,
        string memory baseURI_,
        string memory metadataURI_,
        address metadataResolver_
    ) external returns (AgenticNFT nft) {
        nft = new AgenticNFT(
            name_, symbol_, address(this), policy_, creator_, maxSupply_, baseURI_, metadataURI_, metadataResolver_
        );
    }
}

/// @dev Minimal local view of the migrate selector for fixture helpers.
interface IFacilityMigrate {
    function migrate(address replacement) external;
}
