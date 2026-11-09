// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    FacilityCategory,
    NFT_ESCROW,
    NFT_GAME,
    NFT_LAUNCH,
    NFT_LOCKER,
    NFT_VAULT,
    NPM,
    POOL,
    TREASURY
} from "../../contracts/common/Types.sol";
import {
    AgenticNFTFacilityFactory,
    AgenticNFTVaultTemplateDeployer,
    FacilityTemplateDeployer
} from "../../contracts/facility/AgenticNFTFacilityFactory.sol";
import {AgenticNFTEscrowFacility} from "../../contracts/facility/AgenticNFTEscrowFacility.sol";
import {AgenticNFTGameFacility} from "../../contracts/facility/AgenticNFTGameFacility.sol";
import {AgenticNFTLaunchFacility} from "../../contracts/facility/AgenticNFTLaunchFacility.sol";
import {AgenticNFTLockerFacility} from "../../contracts/facility/AgenticNFTLockerFacility.sol";
import {AgenticNFTVaultFacility} from "../../contracts/facility/AgenticNFTVaultFacility.sol";
import {AgenticVenueRegistry} from "../../contracts/registry/AgenticVenueRegistry.sol";
import {AgenticNFT} from "../../contracts/token/AgenticNFT.sol";

import {NFTFacilityFixture} from "../helpers/NFTFacilityFixture.sol";

contract AgenticNFTFacilityFactoryTest is NFTFacilityFixture {
    bytes32 internal constant UNKNOWN_KIND = keccak256("UNKNOWN_NFT");

    function setUp() public {
        _deployNFTFacilities();
    }

    function _deployers() internal view returns (AgenticNFTFacilityFactory.TemplateDeployers memory) {
        return AgenticNFTFacilityFactory.TemplateDeployers({
            vault: nftFacilities.vaultDeployer(),
            launch: nftFacilities.launchDeployer(),
            locker: nftFacilities.lockerDeployer(),
            game: nftFacilities.gameDeployer(),
            escrow: nftFacilities.escrowDeployer()
        });
    }

    function _deployFactory(AgenticNFTFacilityFactory.TemplateDeployers memory deployers)
        internal
        returns (AgenticNFTFacilityFactory factory)
    {
        factory = AgenticNFTFacilityFactory(
            vm.deployCode(
                "AgenticNFTFacilityFactory.sol:AgenticNFTFacilityFactory",
                abi.encode(address(policy), address(venue), address(nftRegistry), deployers)
            )
        );
    }

    // ------------------------------------------------------------------ wiring

    function testNFTRactoryPolicyAndRegistryWiring() public view {
        assertEq(nftFacilities.policy(), address(policy));
        assertEq(nftFacilities.venueRegistry(), address(venue));
        assertEq(nftFacilities.nftRegistry(), address(nftRegistry));
        assertTrue(nftFacilities.vaultDeployer() != address(0));
        assertTrue(nftFacilities.launchDeployer() != address(0));
        assertTrue(nftFacilities.lockerDeployer() != address(0));
        assertTrue(nftFacilities.gameDeployer() != address(0));
        assertTrue(nftFacilities.escrowDeployer() != address(0));
    }

    function testNFTFactorySupportsOnlyNFTKinds() public view {
        assertTrue(nftFacilities.isSupportedType(NFT_VAULT));
        assertTrue(nftFacilities.isSupportedType(NFT_LAUNCH));
        assertTrue(nftFacilities.isSupportedType(NFT_LOCKER));
        assertTrue(nftFacilities.isSupportedType(NFT_GAME));
        assertTrue(nftFacilities.isSupportedType(NFT_ESCROW));
        assertFalse(nftFacilities.isSupportedType(POOL));
        assertFalse(nftFacilities.isSupportedType(NPM));
        assertFalse(nftFacilities.isSupportedType(TREASURY));
        assertFalse(nftFacilities.isSupportedType(UNKNOWN_KIND));
    }

    function testNFTFactoryCanonicalCodehashExistsForEachKind() public view {
        assertTrue(nftFacilities.codehashOf(NFT_VAULT) != bytes32(0));
        assertTrue(nftFacilities.codehashOf(NFT_LAUNCH) != bytes32(0));
        assertTrue(nftFacilities.codehashOf(NFT_LOCKER) != bytes32(0));
        assertTrue(nftFacilities.codehashOf(NFT_GAME) != bytes32(0));
        assertTrue(nftFacilities.codehashOf(NFT_ESCROW) != bytes32(0));
        assertEq(nftFacilities.codehashOf(UNKNOWN_KIND), bytes32(0));
    }

    // -------------------------------------------------------------- creation

    function testNFTFactoryIsPermissionlessAndRegisters() public {
        vm.prank(nonAgent);
        AgenticNFTVaultFacility vault =
            AgenticNFTVaultFacility(nftFacilities.createFacility(NFT_VAULT, abi.encode(projectOwner)));

        assertEq(vault.factory(), address(nftFacilities));
        assertEq(vault.facilityType(), NFT_VAULT);
        assertEq(vault.owner(), projectOwner);
        assertEq(vault.venueRegistry(), address(venue));
        assertEq(vault.nftRegistry(), address(nftRegistry));
        assertTrue(venue.isFacility(address(vault)));
        assertTrue(venue.isFacilityOfCategory(address(vault), FacilityCategory.CUSTODY));
        assertTrue(venue.isFacilityOfType(address(vault), NFT_VAULT));
        assertEq(venue.factoryOf(address(vault)), address(nftFacilities));
        assertEq(uint8(venue.facilityCategory(address(vault))), uint8(FacilityCategory.CUSTODY));
        assertEq(address(vault).codehash, nftFacilities.codehashOf(NFT_VAULT));
    }

    function testNFTFactoryCreatesEveryKindWithRoles() public {
        AgenticNFTVaultFacility vault = _createNFTVault(projectOwner);
        AgenticNFTLaunchFacility launch = _createNFTLaunch(projectOwner, projectOwner, agent);
        AgenticNFTLockerFacility locker = _createNFTLocker(projectOwner, agent, DEFAULT_UNLOCK_TIME);
        AgenticNFTGameFacility game = _createNFTGame(projectOwner, projectOwner);
        AgenticNFTEscrowFacility escrow = _createNFTEscrow(projectOwner, projectOwner, agent);

        assertEq(vault.facilityType(), NFT_VAULT);
        assertEq(launch.facilityType(), NFT_LAUNCH);
        assertEq(locker.facilityType(), NFT_LOCKER);
        assertEq(game.facilityType(), NFT_GAME);
        assertEq(escrow.facilityType(), NFT_ESCROW);

        assertEq(uint8(venue.facilityCategory(address(vault))), uint8(FacilityCategory.CUSTODY));
        assertEq(uint8(venue.facilityCategory(address(launch))), uint8(FacilityCategory.CUSTODY));
        assertEq(uint8(venue.facilityCategory(address(locker))), uint8(FacilityCategory.CUSTODY));
        assertEq(uint8(venue.facilityCategory(address(game))), uint8(FacilityCategory.PURPOSE));
        assertEq(uint8(venue.facilityCategory(address(escrow))), uint8(FacilityCategory.PURPOSE));

        assertEq(launch.operator(), projectOwner);
        assertEq(launch.beneficiary(), agent);
        assertFalse(launch.closed());
        assertEq(locker.beneficiary(), agent);
        assertEq(locker.unlockTime(), DEFAULT_UNLOCK_TIME);
        assertEq(game.operator(), projectOwner);
        assertEq(escrow.arbiter(), projectOwner);
        assertEq(escrow.beneficiary(), agent);
    }

    function testNFTFactoryAllowsZeroOptionalRoles() public {
        AgenticNFTLaunchFacility launch = _createNFTLaunch(projectOwner, address(0), address(0));
        AgenticNFTGameFacility game = _createNFTGame(projectOwner, address(0));
        AgenticNFTEscrowFacility escrow = _createNFTEscrow(projectOwner, address(0), address(0));

        assertEq(launch.operator(), address(0));
        assertEq(launch.beneficiary(), address(0));
        assertEq(game.operator(), address(0));
        assertEq(escrow.arbiter(), address(0));
        assertEq(escrow.beneficiary(), address(0));
    }

    function testNFTFactoryRejectsZeroLockerBeneficiary() public {
        vm.expectRevert(AgenticNFTFacilityFactory.LockerBeneficiaryRequired.selector);
        nftFacilities.createFacility(NFT_LOCKER, abi.encode(projectOwner, address(0), DEFAULT_UNLOCK_TIME));
    }

    function testNFTFactoryOwnerMayBeProjectWithoutAgentId() public {
        assertFalse(policy.isMember(projectOwner));
        AgenticNFTVaultFacility vault = _createNFTVault(projectOwner);
        assertEq(vault.owner(), projectOwner);
    }

    function testNFTFactoryRejectsUnsupportedKinds() public {
        bytes memory data = abi.encode(projectOwner);

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.UnsupportedFacilityType.selector, POOL));
        nftFacilities.createFacility(POOL, data);

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.UnsupportedFacilityType.selector, NPM));
        nftFacilities.createFacility(NPM, data);

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.UnsupportedFacilityType.selector, TREASURY));
        nftFacilities.createFacility(TREASURY, data);

        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTFacilityFactory.UnsupportedFacilityType.selector, UNKNOWN_KIND)
        );
        nftFacilities.createFacility(UNKNOWN_KIND, data);
    }

    function testNFTFactoryRejectsZeroOwnerForEachKind() public {
        vm.expectRevert(AgenticNFTFacilityFactory.InvalidOwner.selector);
        nftFacilities.createFacility(NFT_VAULT, abi.encode(address(0)));

        vm.expectRevert(AgenticNFTFacilityFactory.InvalidOwner.selector);
        nftFacilities.createFacility(NFT_LAUNCH, abi.encode(address(0), address(0), address(0)));

        vm.expectRevert(AgenticNFTFacilityFactory.InvalidOwner.selector);
        nftFacilities.createFacility(NFT_LOCKER, abi.encode(address(0), address(0), uint64(0)));

        vm.expectRevert(AgenticNFTFacilityFactory.InvalidOwner.selector);
        nftFacilities.createFacility(NFT_GAME, abi.encode(address(0), address(0)));

        vm.expectRevert(AgenticNFTFacilityFactory.InvalidOwner.selector);
        nftFacilities.createFacility(NFT_ESCROW, abi.encode(address(0), address(0), address(0)));
    }

    function testNFTFactoryRejectsNonAgentBeneficiaries() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.AgentRequired.selector, nonAgent));
        nftFacilities.createFacility(NFT_LAUNCH, abi.encode(projectOwner, projectOwner, nonAgent));

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.AgentRequired.selector, nonAgent));
        nftFacilities.createFacility(NFT_LOCKER, abi.encode(projectOwner, nonAgent, DEFAULT_UNLOCK_TIME));

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.AgentRequired.selector, nonAgent));
        nftFacilities.createFacility(NFT_ESCROW, abi.encode(projectOwner, projectOwner, nonAgent));
    }

    function testNFTFactoryRejectsFacilityAsBeneficiary() public {
        AgenticNFTVaultFacility vault = _createNFTVault(projectOwner);
        address facility = address(vault);

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.FacilityNotAgent.selector, facility));
        nftFacilities.createFacility(NFT_LAUNCH, abi.encode(projectOwner, projectOwner, facility));

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.FacilityNotAgent.selector, facility));
        nftFacilities.createFacility(NFT_LOCKER, abi.encode(projectOwner, facility, DEFAULT_UNLOCK_TIME));

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.FacilityNotAgent.selector, facility));
        nftFacilities.createFacility(NFT_ESCROW, abi.encode(projectOwner, projectOwner, facility));
    }

    function testNFTFactoryRejectsRevokedFacilityWithAgentIdAsBeneficiary() public {
        AgenticNFTVaultFacility revoked = _createNFTVault(projectOwner);
        identityAdapter.setHasIdentity(address(revoked), true);
        _revokeNFTFacility(address(revoked));

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.FacilityNotAgent.selector, address(revoked)));
        nftFacilities.createFacility(NFT_LAUNCH, abi.encode(projectOwner, projectOwner, address(revoked)));
    }

    function testNFTFactoryRejectsMalformedInitData() public {
        vm.expectRevert();
        nftFacilities.createFacility(NFT_VAULT, hex"1234");

        vm.expectRevert();
        nftFacilities.createFacility(NFT_LAUNCH, abi.encode(projectOwner));

        vm.expectRevert();
        nftFacilities.createFacility(NFT_LOCKER, abi.encode(projectOwner));

        vm.expectRevert();
        nftFacilities.createFacility(NFT_GAME, hex"1234");

        vm.expectRevert();
        nftFacilities.createFacility(NFT_ESCROW, abi.encode(projectOwner));
    }

    // ------------------------------------------------------------- codehash

    function testNFTFactorySameKindFacilitiesShareCodehash() public {
        AgenticNFTVaultFacility first = _createNFTVault(projectOwner);
        AgenticNFTVaultFacility second = _createNFTVault(agent);

        assertEq(address(first).codehash, address(second).codehash);
        assertEq(address(first).codehash, nftFacilities.codehashOf(NFT_VAULT));
        assertEq(address(second).codehash, nftFacilities.codehashOf(NFT_VAULT));
    }

    function testNFTFactorySameKindCodehashForEveryKind() public {
        assertEq(address(_createNFTVault(projectOwner)).codehash, address(_createNFTVault(agent)).codehash);

        assertEq(
            address(_createNFTLaunch(projectOwner, projectOwner, agent)).codehash,
            address(_createNFTLaunch(agent, agent, agent2)).codehash
        );

        assertEq(
            address(_createNFTLocker(projectOwner, agent, DEFAULT_UNLOCK_TIME)).codehash,
            address(_createNFTLocker(agent, agent2, DEFAULT_UNLOCK_TIME + 1)).codehash
        );

        assertEq(
            address(_createNFTGame(projectOwner, projectOwner)).codehash, address(_createNFTGame(agent, agent)).codehash
        );

        assertEq(
            address(_createNFTEscrow(projectOwner, projectOwner, agent)).codehash,
            address(_createNFTEscrow(agent, agent, agent2)).codehash
        );
    }

    function testNFTFactoryDifferentKindsHaveDifferentCodehash() public {
        AgenticNFTVaultFacility vault = _createNFTVault(projectOwner);
        AgenticNFTGameFacility game = _createNFTGame(projectOwner, projectOwner);
        AgenticNFTEscrowFacility escrow = _createNFTEscrow(projectOwner, projectOwner, agent);

        assertTrue(address(vault).codehash != address(game).codehash);
        assertTrue(address(game).codehash != address(escrow).codehash);
    }

    function testNFTFactoryAllKindsMatchCanonicalCodehash() public {
        assertEq(address(_createNFTVault(projectOwner)).codehash, nftFacilities.codehashOf(NFT_VAULT));
        assertEq(
            address(_createNFTLaunch(projectOwner, projectOwner, agent)).codehash, nftFacilities.codehashOf(NFT_LAUNCH)
        );
        assertEq(
            address(_createNFTLocker(projectOwner, agent, DEFAULT_UNLOCK_TIME)).codehash,
            nftFacilities.codehashOf(NFT_LOCKER)
        );
        assertEq(address(_createNFTGame(projectOwner, projectOwner)).codehash, nftFacilities.codehashOf(NFT_GAME));
        assertEq(
            address(_createNFTEscrow(projectOwner, projectOwner, agent)).codehash, nftFacilities.codehashOf(NFT_ESCROW)
        );
    }

    function testNFTFactoryCodehashIncludesFactoryAddress() public {
        AgenticNFTFacilityFactory second = _deployFactory(_deployers());
        venue.setRegistrar(address(second), FacilityCategory.CUSTODY, true);
        venue.setRegistrar(address(second), FacilityCategory.PURPOSE, true);

        AgenticNFTVaultFacility firstVault = _createNFTVault(projectOwner);
        AgenticNFTVaultFacility secondVault =
            AgenticNFTVaultFacility(second.createFacility(NFT_VAULT, abi.encode(projectOwner)));

        assertTrue(address(firstVault).codehash != address(secondVault).codehash);
        assertEq(address(secondVault).codehash, second.codehashOf(NFT_VAULT));
        assertEq(secondVault.factory(), address(second));
    }

    function testNFTFactoryRegistrationRequiresRegistrar() public {
        AgenticNFTFacilityFactory unregistered = _deployFactory(_deployers());

        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticVenueRegistry.NotRegistrar.selector, address(unregistered), FacilityCategory.CUSTODY
            )
        );
        unregistered.createFacility(NFT_VAULT, abi.encode(projectOwner));
    }

    function testNFTFactoryNeverHoldsNFTs() public {
        AgenticNFTVaultFacility vault = _createNFTVault(projectOwner);
        AgenticNFT nft = _createNFTCollection();
        _mintNFT(nft, address(vault));

        assertEq(nft.balanceOf(address(vault)), 1);
        assertEq(nft.balanceOf(address(nftFacilities)), 0);
        assertEq(address(nftFacilities).balance, 0);
        assertFalse(policy.isFacility(address(nftFacilities)));
    }

    // --------------------------------------------------------- construction

    function testNFTFactoryRejectsZeroRegistries() public {
        AgenticNFTFacilityFactory.TemplateDeployers memory deployers = _deployers();

        vm.expectRevert(AgenticNFTFacilityFactory.ZeroAddress.selector);
        vm.deployCode(
            "AgenticNFTFacilityFactory.sol:AgenticNFTFacilityFactory",
            abi.encode(address(0), address(venue), address(nftRegistry), deployers)
        );

        vm.expectRevert(AgenticNFTFacilityFactory.ZeroAddress.selector);
        vm.deployCode(
            "AgenticNFTFacilityFactory.sol:AgenticNFTFacilityFactory",
            abi.encode(address(policy), address(0), address(nftRegistry), deployers)
        );

        vm.expectRevert(AgenticNFTFacilityFactory.ZeroAddress.selector);
        vm.deployCode(
            "AgenticNFTFacilityFactory.sol:AgenticNFTFacilityFactory",
            abi.encode(address(policy), address(venue), address(0), deployers)
        );
    }

    function testNFTFactoryRejectsCodelessRegistries() public {
        AgenticNFTFacilityFactory.TemplateDeployers memory deployers = _deployers();

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.RegistryHasNoCode.selector, nonAgent));
        vm.deployCode(
            "AgenticNFTFacilityFactory.sol:AgenticNFTFacilityFactory",
            abi.encode(nonAgent, address(venue), address(nftRegistry), deployers)
        );

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.RegistryHasNoCode.selector, nonAgent));
        vm.deployCode(
            "AgenticNFTFacilityFactory.sol:AgenticNFTFacilityFactory",
            abi.encode(address(policy), nonAgent, address(nftRegistry), deployers)
        );

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.RegistryHasNoCode.selector, nonAgent));
        vm.deployCode(
            "AgenticNFTFacilityFactory.sol:AgenticNFTFacilityFactory",
            abi.encode(address(policy), address(venue), nonAgent, deployers)
        );
    }

    function testNFTFactoryRejectsZeroDeployer() public {
        AgenticNFTFacilityFactory.TemplateDeployers memory deployers = _deployers();
        deployers.vault = address(0);

        vm.expectRevert(AgenticNFTFacilityFactory.ZeroAddress.selector);
        vm.deployCode(
            "AgenticNFTFacilityFactory.sol:AgenticNFTFacilityFactory",
            abi.encode(address(policy), address(venue), address(nftRegistry), deployers)
        );
    }

    function testNFTFactoryRejectsCodelessDeployer() public {
        AgenticNFTFacilityFactory.TemplateDeployers memory deployers = _deployers();
        deployers.vault = nonAgent;

        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.DeployerHasNoCode.selector, nonAgent));
        vm.deployCode(
            "AgenticNFTFacilityFactory.sol:AgenticNFTFacilityFactory",
            abi.encode(address(policy), address(venue), address(nftRegistry), deployers)
        );
    }

    function testNFTFactoryDeployHelperOnlyFactory() public {
        AgenticNFTVaultTemplateDeployer helper = AgenticNFTVaultTemplateDeployer(nftFacilities.vaultDeployer());

        vm.expectRevert(abi.encodeWithSelector(FacilityTemplateDeployer.NotFactory.selector, address(this)));
        helper.deploy(address(nftFacilities), address(venue), address(nftRegistry), projectOwner);
    }
}
