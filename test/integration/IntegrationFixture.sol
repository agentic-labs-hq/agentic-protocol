// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {
    ESCROW,
    FacilityCategory,
    GAME,
    LAUNCH,
    LENDING,
    LOCKER,
    NPM,
    POOL,
    TREASURY,
    VAULT
} from "../../contracts/common/Types.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";
import {AgenticTokenFactory} from "../../contracts/token/AgenticTokenFactory.sol";
import {AgenticPolicy} from "../../contracts/policy/AgenticPolicy.sol";
import {AgenticPolicyRegistry} from "../../contracts/policy/AgenticPolicyRegistry.sol";
import {AgenticAssetRegistry} from "../../contracts/registry/AgenticAssetRegistry.sol";
import {AgenticQuoteAssetRegistry} from "../../contracts/registry/AgenticQuoteAssetRegistry.sol";
import {AgenticVenueRegistry} from "../../contracts/registry/AgenticVenueRegistry.sol";
import {AgenticIdentityRegistry} from "../../contracts/identity/AgenticIdentityRegistry.sol";
import {AgenticIdAdapter} from "../../contracts/identity/AgenticIdAdapter.sol";
import {AGENT_ID_KIND} from "../../contracts/identity/IAgentIdRegistry.sol";
import {MockAgentId} from "../../contracts/identity/mocks/MockAgentId.sol";
import {
    AgenticEscrowTemplateDeployer,
    AgenticFacilityFactory,
    AgenticGameTemplateDeployer,
    AgenticLaunchTemplateDeployer,
    AgenticLendingTemplateDeployer,
    AgenticLockerTemplateDeployer,
    AgenticVaultTemplateDeployer
} from "../../contracts/facility/AgenticFacilityFactory.sol";
import {AgenticVaultFacility} from "../../contracts/facility/AgenticVaultFacility.sol";
import {AgenticGameFacility} from "../../contracts/facility/AgenticGameFacility.sol";
import {AgenticLaunchFacility} from "../../contracts/facility/AgenticLaunchFacility.sol";
import {AgenticLockerFacility} from "../../contracts/facility/AgenticLockerFacility.sol";
import {AgenticEscrowFacility} from "../../contracts/facility/AgenticEscrowFacility.sol";
import {AgenticLendingFacility} from "../../contracts/facility/AgenticLendingFacility.sol";
import {AgenticTreasury} from "../../contracts/treasury/AgenticTreasury.sol";
import {MockSwapRouter} from "../mocks/MockSwapRouter.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {MockVenueAccount} from "../mocks/MockVenueAccount.sol";

/// @notice fixture: real protocol–stack, no mock identity/policy/venue.
abstract contract IntegrationFixture is Test {
    AgenticVenueRegistry internal venue;
    AgenticPolicy internal policy;
    AgenticIdentityRegistry internal identityRegistry;
    AgenticIdAdapter internal identityAdapter;
    MockAgentId internal agentId;
    AgenticPolicyRegistry internal policyRegistry;
    AgenticAssetRegistry internal assetRegistry;
    AgenticQuoteAssetRegistry internal quoteRegistry;
    AgenticTokenFactory internal tokenFactory;
    AgenticTreasury internal treasury;
    AgenticFacilityFactory internal facilities;
    MockSwapRouter internal router;

    address internal agent = address(0xA11CE);
    address internal agent2 = address(0xB0B);
    address internal projectOwner = address(0xF00D);
    address internal nonAgent = address(0xBAD);

    MockVenueAccount internal pool;
    MockVenueAccount internal lpManager;
    MockVenueAccount internal feeReplacement;

    AgenticVaultFacility internal vault;
    AgenticGameFacility internal game;

    uint256 internal constant MAX_ADAPTERS = 8;
    uint256 internal constant MAX_POLICIES = 8;
    uint256 internal constant MAX_POOLS = 4;
    uint256 internal constant MAX_QUOTE_ASSETS = 8;
    uint256 internal constant MAX_RECIPIENTS = 8;
    uint256 internal constant MAX_BATCH = 16;
    uint256 internal constant MAX_FACILITY_RECIPIENTS = 8;

    function setUp() public virtual {
        _deployIntegration();
    }

    function _deployIntegration() internal {
        // Real identity stack: mock registry -> real adapter -> real registry.
        agentId = new MockAgentId();
        agentId.setIdentity(agent, "agent");
        agentId.setIdentity(agent2, "agent2");
        identityAdapter = new AgenticIdAdapter(agentId);
        identityRegistry = new AgenticIdentityRegistry(MAX_ADAPTERS);
        identityRegistry.registerAdapter(address(identityAdapter), AGENT_ID_KIND);

        venue = new AgenticVenueRegistry(address(this));
        venue.addTypeCategory(POOL, FacilityCategory.POOL);
        venue.addTypeCategory(NPM, FacilityCategory.LP_MANAGER);
        venue.addTypeCategory(TREASURY, FacilityCategory.FEE_RECIPIENT);
        venue.addTypeCategory(VAULT, FacilityCategory.CUSTODY);
        venue.addTypeCategory(LAUNCH, FacilityCategory.CUSTODY);
        venue.addTypeCategory(LOCKER, FacilityCategory.CUSTODY);
        venue.addTypeCategory(GAME, FacilityCategory.PURPOSE);
        venue.addTypeCategory(ESCROW, FacilityCategory.PURPOSE);
        venue.addTypeCategory(LENDING, FacilityCategory.PURPOSE);

        policy = new AgenticPolicy(address(identityRegistry), address(venue));
        policyRegistry = new AgenticPolicyRegistry(address(this), MAX_POLICIES);
        policyRegistry.addPolicy(address(policy), 1);
        policyRegistry.setCurrentPolicy(address(policy));

        assetRegistry = new AgenticAssetRegistry(address(this), address(policyRegistry), address(venue), MAX_POOLS);
        tokenFactory =
            new AgenticTokenFactory(address(policyRegistry), address(assetRegistry), address(venue), MAX_RECIPIENTS);
        assetRegistry.setRegistrar(address(tokenFactory), true);

        quoteRegistry =
            new AgenticQuoteAssetRegistry(address(this), address(assetRegistry), MAX_QUOTE_ASSETS, new address[](0));

        router = new MockSwapRouter();
        treasury =
            new AgenticTreasury(address(assetRegistry), address(venue), address(router), MAX_BATCH, address(this));

        venue.setRegistrar(address(this), FacilityCategory.POOL, true);
        venue.setRegistrar(address(this), FacilityCategory.LP_MANAGER, true);
        venue.setRegistrar(address(this), FacilityCategory.FEE_RECIPIENT, true);

        pool = new MockVenueAccount();
        lpManager = new MockVenueAccount();
        feeReplacement = new MockVenueAccount();
        venue.registerFacility(address(pool), POOL);
        venue.registerFacility(address(lpManager), NPM);
        venue.registerFacility(address(treasury), TREASURY);
        venue.registerFacility(address(feeReplacement), TREASURY);

        AgenticFacilityFactory.TemplateDeployers memory deployers = AgenticFacilityFactory.TemplateDeployers({
            vault: address(new AgenticVaultTemplateDeployer()),
            launch: address(new AgenticLaunchTemplateDeployer()),
            locker: address(new AgenticLockerTemplateDeployer()),
            game: address(new AgenticGameTemplateDeployer()),
            escrow: address(new AgenticEscrowTemplateDeployer()),
            lending: address(new AgenticLendingTemplateDeployer())
        });
        facilities = new AgenticFacilityFactory(address(policy), address(venue), address(assetRegistry), deployers);

        venue.setRegistrar(address(facilities), FacilityCategory.CUSTODY, true);
        venue.setRegistrar(address(facilities), FacilityCategory.PURPOSE, true);

        vault = _createVault(address(this));
        game = _createGame(address(this), address(this));
    }

    function _createVault(address owner_) internal returns (AgenticVaultFacility) {
        return AgenticVaultFacility(payable(facilities.createFacility(VAULT, abi.encode(owner_))));
    }

    function _createGame(address owner_, address operator_) internal returns (AgenticGameFacility) {
        return AgenticGameFacility(facilities.createFacility(GAME, abi.encode(owner_, operator_)));
    }

    function _createToken(address[] memory recipients, uint256[] memory amounts) internal returns (AgenticToken token) {
        vm.prank(projectOwner);
        token = AgenticToken(
            tokenFactory.createToken("Integration Token", "IT", address(0), recipients, amounts, "ipfs://integration")
        );
    }

    function _createTokenFor(address recipient, uint256 amount) internal returns (AgenticToken) {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = recipient;
        amounts[0] = amount;
        return _createToken(recipients, amounts);
    }

    function _fundPoolWithGated(AgenticToken token, uint256 amount) internal {
        vm.prank(agent);
        token.transfer(address(pool), amount);
        vm.prank(address(pool));
        token.transfer(address(treasury), amount);
    }
}
