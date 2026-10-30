// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ESCROW, FacilityCategory, GAME, LAUNCH, LENDING, LOCKER, VAULT} from "../../contracts/common/Types.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";
import {AgenticEscrowFacility} from "../../contracts/facility/AgenticEscrowFacility.sol";
import {AgenticFacilityFactory} from "../../contracts/facility/AgenticFacilityFactory.sol";
import {AgenticGameFacility} from "../../contracts/facility/AgenticGameFacility.sol";
import {AgenticLaunchFacility} from "../../contracts/facility/AgenticLaunchFacility.sol";
import {AgenticLendingFacility} from "../../contracts/facility/AgenticLendingFacility.sol";
import {AgenticLockerFacility} from "../../contracts/facility/AgenticLockerFacility.sol";
import {AgenticVaultFacility} from "../../contracts/facility/AgenticVaultFacility.sol";

import {MockToken} from "../mocks/MockToken.sol";
import {TokenAssetFixture} from "./TokenAssetFixture.sol";

/// @notice fixture: the real protocol–stack plus the real facility factory
/// and its six template deployment helpers.
abstract contract FacilityFixture is TokenAssetFixture {
    AgenticFacilityFactory internal facilities;

    uint64 internal constant DEFAULT_UNLOCK_TIME = 2_000_000_000;

    /// @dev Deploy the standard facility factory and make it the CUSTODY/PURPOSE
    /// registrar. Deployers are deployed from artifacts so the fixture bytecode
    /// does not embed six template creation codes.
    function _deployFacilities() internal {
        _deployTokenAsset();

        // venue's shared fixture maps VAULT/LAUNCH/GAME/ESCROW only.
        venue.addTypeCategory(LOCKER, FacilityCategory.CUSTODY);
        venue.addTypeCategory(LENDING, FacilityCategory.PURPOSE);

        AgenticFacilityFactory.TemplateDeployers memory deployers = AgenticFacilityFactory.TemplateDeployers({
            vault: vm.deployCode("AgenticFacilityFactory.sol:AgenticVaultTemplateDeployer"),
            launch: vm.deployCode("AgenticFacilityFactory.sol:AgenticLaunchTemplateDeployer"),
            locker: vm.deployCode("AgenticFacilityFactory.sol:AgenticLockerTemplateDeployer"),
            game: vm.deployCode("AgenticFacilityFactory.sol:AgenticGameTemplateDeployer"),
            escrow: vm.deployCode("AgenticFacilityFactory.sol:AgenticEscrowTemplateDeployer"),
            lending: vm.deployCode("AgenticFacilityFactory.sol:AgenticLendingTemplateDeployer")
        });
        facilities = AgenticFacilityFactory(
            vm.deployCode(
                "AgenticFacilityFactory.sol:AgenticFacilityFactory",
                abi.encode(address(policy), address(venue), address(assetRegistry), deployers)
            )
        );

        venue.setRegistrar(address(facilities), FacilityCategory.CUSTODY, true);
        venue.setRegistrar(address(facilities), FacilityCategory.PURPOSE, true);
    }

    // ---------------------------------------------------------------- factory

    function _createVault(address owner_) internal returns (AgenticVaultFacility facility) {
        facility = AgenticVaultFacility(payable(facilities.createFacility(VAULT, abi.encode(owner_))));
    }

    function _createLaunch(address owner_, address operator_, address beneficiary_)
        internal
        returns (AgenticLaunchFacility facility)
    {
        facility = AgenticLaunchFacility(
            payable(facilities.createFacility(LAUNCH, abi.encode(owner_, operator_, beneficiary_)))
        );
    }

    function _createLocker(address owner_, address beneficiary_, uint64 unlockTime_)
        internal
        returns (AgenticLockerFacility facility)
    {
        facility = AgenticLockerFacility(
            facilities.createFacility(LOCKER, abi.encode(owner_, beneficiary_, unlockTime_))
        );
    }

    function _createGame(address owner_, address operator_) internal returns (AgenticGameFacility facility) {
        facility = AgenticGameFacility(facilities.createFacility(GAME, abi.encode(owner_, operator_)));
    }

    function _createEscrow(address owner_, address arbiter_, address beneficiary_, address depositor_)
        internal
        returns (AgenticEscrowFacility facility)
    {
        facility = AgenticEscrowFacility(
            facilities.createFacility(ESCROW, abi.encode(owner_, arbiter_, beneficiary_, depositor_))
        );
    }

    function _createLending(address owner_, address keeper_, address oracle_, address lender_, address borrower_)
        internal
        returns (AgenticLendingFacility facility)
    {
        facility = AgenticLendingFacility(
            facilities.createFacility(LENDING, abi.encode(owner_, keeper_, oracle_, lender_, borrower_))
        );
    }

    function _defaultVault() internal returns (AgenticVaultFacility) {
        return _createVault(projectOwner);
    }

    function _defaultLaunch() internal returns (AgenticLaunchFacility) {
        return _createLaunch(projectOwner, projectOwner, agent);
    }

    function _defaultLocker() internal returns (AgenticLockerFacility) {
        return _createLocker(projectOwner, agent, DEFAULT_UNLOCK_TIME);
    }

    function _defaultGame() internal returns (AgenticGameFacility) {
        return _createGame(projectOwner, projectOwner);
    }

    function _defaultEscrow() internal returns (AgenticEscrowFacility) {
        return _createEscrow(projectOwner, projectOwner, agent, agent);
    }

    function _defaultLending() internal returns (AgenticLendingFacility) {
        return _createLending(projectOwner, projectOwner, projectOwner, agent, agent2);
    }

    // ----------------------------------------------------------------- tokens

    /// @dev Create a gated token whose initial supply is held by `recipient`
    /// (must be an agent or an active CUSTODY/PURPOSE facility).
    function _gatedTo(address recipient, uint256 amount) internal returns (AgenticToken token) {
        token = AgenticToken(_createTokenFor(agent, recipient, amount));
    }

    /// @dev Create a gated token held by an agent, for deposit/repay flows.
    function _gatedToAgent(address recipient, uint256 amount) internal returns (AgenticToken token) {
        token = AgenticToken(_createTokenFor(agent, recipient, amount));
    }

    /// @dev Create a registered gated token with an explicit (possibly
    /// permissive) policy. Used to prove the facility's canonical-policy guard
    /// is independent of the token's own policy.
    function _gatedToWithPolicy(address recipient, address policy_, uint256 amount)
        internal
        returns (AgenticToken token)
    {
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = recipient;
        amounts[0] = amount;
        token = AgenticToken(_createToken(agent, policy_, recipients, amounts, DEFAULT_URI));
    }

    /// @dev Plain public (non-gated) ERC-20 held by `recipient`.
    function _publicTokenTo(address recipient, uint256 amount) internal returns (MockToken token) {
        token = new MockToken();
        token.mint(recipient, amount);
    }

    function _fundVault(AgenticVaultFacility facility, uint256 amount) internal returns (AgenticToken token) {
        token = _gatedTo(address(facility), amount);
    }

    function _fundLaunch(AgenticLaunchFacility facility, uint256 amount) internal returns (AgenticToken token) {
        token = _gatedTo(address(facility), amount);
    }

    function _fundLocker(AgenticLockerFacility facility, uint256 amount) internal returns (AgenticToken token) {
        token = _gatedTo(address(facility), amount);
    }

    function _fundGame(AgenticGameFacility facility, uint256 amount) internal returns (AgenticToken token) {
        token = _gatedTo(address(facility), amount);
    }

    // -------------------------------------------------------------- migration

    /// @dev Registry replacement must be set by the facility owner itself.
    function _setReplacement(address facility, address replacement) internal {
        vm.prank(projectOwner);
        venue.setReplacement(facility, replacement);
    }

    function _revoke(address facility) internal {
        venue.revokeFacility(facility);
    }
}
