// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {FacilityCategory, GAME, LAUNCH, NPM, POOL, TREASURY, VAULT} from "../../contracts/common/Types.sol";
import {NonRevocableFacility} from "../../contracts/common/Errors.sol";
import {Governance2Step} from "../../contracts/common/Governance2Step.sol";
import {AgenticVenueRegistry} from "../../contracts/registry/AgenticVenueRegistry.sol";
import {MockFacility} from "../mocks/MockFacility.sol";
import {MockFacilityFactory} from "../mocks/MockFacilityFactory.sol";
import {MockProxyFacility} from "../mocks/MockProxyFacility.sol";
import {MockVenueAccount} from "../mocks/MockVenueAccount.sol";

contract AgenticVenueRegistryTest is Test {
    event TypeCategoryAdded(bytes32 indexed kind, FacilityCategory category);
    event RegistrarSet(address indexed account, FacilityCategory indexed category, bool enabled);
    event FacilityRegistered(
        address indexed account, bytes32 indexed kind, FacilityCategory indexed category, address factory
    );
    event FacilityRevoked(address indexed account, bytes32 indexed kind);
    event ReplacementSet(address indexed account, address indexed replacement);
    event GovernanceTransferStarted(address indexed current, address indexed pending);
    event GovernanceTransferred(address indexed previous, address indexed newGovernance);

    bytes32 internal constant OTHER_TREASURY = keccak256("TREASURY_2");

    AgenticVenueRegistry internal venue;
    MockFacilityFactory internal factory;

    address internal nonGov = address(0xBAD);
    address internal projectOwner = address(0xF00D);

    function setUp() public {
        venue = new AgenticVenueRegistry(address(this));
        factory = new MockFacilityFactory(address(0));
    }

    // ---------------------------------------------------------------- helpers

    function _map(bytes32 kind, FacilityCategory category) internal {
        venue.addTypeCategory(kind, category);
    }

    function _setRegistrar(address account, FacilityCategory category) internal {
        venue.setRegistrar(account, category, true);
    }

    function _registerTrusted(bytes32 kind) internal returns (MockVenueAccount account) {
        account = new MockVenueAccount();
        venue.registerFacility(address(account), kind);
    }

    function _createFacility(bytes32 kind, address owner_) internal returns (MockFacility facility) {
        facility = MockFacility(factory.createFacility(kind, abi.encode(owner_)));
    }

    function _createRegisteredFacility(bytes32 kind, address owner_) internal returns (MockFacility facility) {
        facility = _createFacility(kind, owner_);
        vm.prank(address(factory));
        venue.registerFacility(address(facility), kind);
    }

    function _setupCustody() internal {
        _map(VAULT, FacilityCategory.CUSTODY);
        _map(LAUNCH, FacilityCategory.CUSTODY);
        _setRegistrar(address(factory), FacilityCategory.CUSTODY);
    }

    // ----------------------------------------------------------- type/category

    function testInitialState() public view {
        assertEq(venue.governance(), address(this));
        assertEq(venue.pendingGovernance(), address(0));
    }

    function testAddTypeCategory() public {
        vm.expectEmit(true, false, false, true, address(venue));
        emit TypeCategoryAdded(POOL, FacilityCategory.POOL);
        _map(POOL, FacilityCategory.POOL);

        assertEq(uint256(venue.categoryOfType(POOL)), uint256(FacilityCategory.POOL));
    }

    function testAddTypeCategoryAllFive() public {
        _map(POOL, FacilityCategory.POOL);
        _map(NPM, FacilityCategory.LP_MANAGER);
        _map(TREASURY, FacilityCategory.FEE_RECIPIENT);
        _map(VAULT, FacilityCategory.CUSTODY);
        _map(GAME, FacilityCategory.PURPOSE);

        assertEq(uint256(venue.categoryOfType(POOL)), uint256(FacilityCategory.POOL));
        assertEq(uint256(venue.categoryOfType(NPM)), uint256(FacilityCategory.LP_MANAGER));
        assertEq(uint256(venue.categoryOfType(TREASURY)), uint256(FacilityCategory.FEE_RECIPIENT));
        assertEq(uint256(venue.categoryOfType(VAULT)), uint256(FacilityCategory.CUSTODY));
        assertEq(uint256(venue.categoryOfType(GAME)), uint256(FacilityCategory.PURPOSE));
    }

    function testNewSubtypeUnderExistingCategory() public {
        _map(VAULT, FacilityCategory.CUSTODY);
        _map(LAUNCH, FacilityCategory.CUSTODY);
        assertEq(uint256(venue.categoryOfType(VAULT)), uint256(FacilityCategory.CUSTODY));
        assertEq(uint256(venue.categoryOfType(LAUNCH)), uint256(FacilityCategory.CUSTODY));
    }

    function testAddTypeCategoryOnlyGovernance() public {
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonGov));
        venue.addTypeCategory(POOL, FacilityCategory.POOL);
    }

    function testAddTypeCategoryZeroKind() public {
        vm.expectRevert(AgenticVenueRegistry.ZeroKind.selector);
        venue.addTypeCategory(bytes32(0), FacilityCategory.POOL);
    }

    function testAddTypeCategoryNoneCategory() public {
        vm.expectRevert(AgenticVenueRegistry.CategoryNone.selector);
        venue.addTypeCategory(POOL, FacilityCategory.NONE);
    }

    function testAddTypeCategoryAppendOnlySameCategory() public {
        _map(POOL, FacilityCategory.POOL);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticVenueRegistry.TypeAlreadyMapped.selector, POOL, FacilityCategory.POOL)
        );
        venue.addTypeCategory(POOL, FacilityCategory.POOL);
        assertEq(uint256(venue.categoryOfType(POOL)), uint256(FacilityCategory.POOL));
    }

    function testAddTypeCategoryAppendOnlyCannotRemap() public {
        _map(POOL, FacilityCategory.POOL);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticVenueRegistry.TypeAlreadyMapped.selector, POOL, FacilityCategory.POOL)
        );
        venue.addTypeCategory(POOL, FacilityCategory.FEE_RECIPIENT);
        assertEq(uint256(venue.categoryOfType(POOL)), uint256(FacilityCategory.POOL));
    }

    // --------------------------------------------------------------- registrars

    function testSetRegistrar() public {
        vm.expectEmit(true, true, false, true, address(venue));
        emit RegistrarSet(address(this), FacilityCategory.POOL, true);
        venue.setRegistrar(address(this), FacilityCategory.POOL, true);
        assertTrue(venue.isRegistrarFor(address(this), FacilityCategory.POOL));

        vm.expectEmit(true, true, false, true, address(venue));
        emit RegistrarSet(address(this), FacilityCategory.POOL, false);
        venue.setRegistrar(address(this), FacilityCategory.POOL, false);
        assertFalse(venue.isRegistrarFor(address(this), FacilityCategory.POOL));
    }

    function testSetRegistrarIsPerCategory() public {
        venue.setRegistrar(address(this), FacilityCategory.POOL, true);
        assertTrue(venue.isRegistrarFor(address(this), FacilityCategory.POOL));
        assertFalse(venue.isRegistrarFor(address(this), FacilityCategory.LP_MANAGER));
    }

    function testSetRegistrarOnlyGovernance() public {
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonGov));
        venue.setRegistrar(nonGov, FacilityCategory.POOL, true);
    }

    function testSetRegistrarZeroAccount() public {
        vm.expectRevert(AgenticVenueRegistry.ZeroAccount.selector);
        venue.setRegistrar(address(0), FacilityCategory.POOL, true);
    }

    function testSetRegistrarNoneCategory() public {
        vm.expectRevert(AgenticVenueRegistry.CategoryNone.selector);
        venue.setRegistrar(address(this), FacilityCategory.NONE, true);
    }

    function testSetRegistrarRequiresCode() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticVenueRegistry.AccountHasNoCode.selector, nonGov));
        venue.setRegistrar(nonGov, FacilityCategory.POOL, true);
    }

    // ----------------------------------------------------------- trusted venues

    function testRegisterPOOL() public {
        _map(POOL, FacilityCategory.POOL);
        _setRegistrar(address(this), FacilityCategory.POOL);
        MockVenueAccount account = new MockVenueAccount();

        vm.expectEmit(true, true, true, true, address(venue));
        emit FacilityRegistered(address(account), POOL, FacilityCategory.POOL, address(this));
        venue.registerFacility(address(account), POOL);

        assertTrue(venue.isFacility(address(account)));
        assertTrue(venue.isFacilityOfCategory(address(account), FacilityCategory.POOL));
        assertTrue(venue.isFacilityOfType(address(account), POOL));
        assertFalse(venue.isRevokedFacility(address(account)));
        assertEq(venue.facilityType(address(account)), POOL);
        assertEq(uint256(venue.facilityCategory(address(account))), uint256(FacilityCategory.POOL));
        assertEq(venue.factoryOf(address(account)), address(this));
        assertEq(venue.replacementOf(address(account)), address(0));
    }

    function testRegisterLPManager() public {
        _map(NPM, FacilityCategory.LP_MANAGER);
        _setRegistrar(address(this), FacilityCategory.LP_MANAGER);
        MockVenueAccount account = _registerTrusted(NPM);
        assertTrue(venue.isFacilityOfCategory(address(account), FacilityCategory.LP_MANAGER));
    }

    function testRegisterFEERecipient() public {
        _map(TREASURY, FacilityCategory.FEE_RECIPIENT);
        _setRegistrar(address(this), FacilityCategory.FEE_RECIPIENT);
        MockVenueAccount account = _registerTrusted(TREASURY);
        assertTrue(venue.isFacilityOfCategory(address(account), FacilityCategory.FEE_RECIPIENT));
        assertEq(venue.factoryOf(address(account)), address(this));
    }

    function testRegisterRequiresRegistrar() public {
        _map(POOL, FacilityCategory.POOL);
        MockVenueAccount account = new MockVenueAccount();
        vm.prank(nonGov);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticVenueRegistry.NotRegistrar.selector, nonGov, FacilityCategory.POOL)
        );
        venue.registerFacility(address(account), POOL);
    }

    function testRegisterRequiresCode() public {
        _map(POOL, FacilityCategory.POOL);
        _setRegistrar(address(this), FacilityCategory.POOL);
        vm.expectRevert(abi.encodeWithSelector(AgenticVenueRegistry.AccountHasNoCode.selector, nonGov));
        venue.registerFacility(nonGov, POOL);
    }

    function testRegisterUnmappedKind() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticVenueRegistry.TypeNotMapped.selector, POOL));
        venue.registerFacility(address(this), POOL);
    }

    function testRegisterDuplicate() public {
        _map(POOL, FacilityCategory.POOL);
        _setRegistrar(address(this), FacilityCategory.POOL);
        MockVenueAccount account = _registerTrusted(POOL);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticVenueRegistry.FacilityAlreadyRegistered.selector, address(account))
        );
        venue.registerFacility(address(account), POOL);
    }

    // ------------------------------------------------------- custody / purpose

    function testRegisterCustody() public {
        _setupCustody();
        MockFacility facility = _createFacility(VAULT, projectOwner);

        vm.expectEmit(true, true, true, true, address(venue));
        emit FacilityRegistered(address(facility), VAULT, FacilityCategory.CUSTODY, address(factory));
        vm.prank(address(factory));
        venue.registerFacility(address(facility), VAULT);

        assertTrue(venue.isFacility(address(facility)));
        assertTrue(venue.isFacilityOfCategory(address(facility), FacilityCategory.CUSTODY));
        assertTrue(venue.isFacilityOfType(address(facility), VAULT));
        assertEq(venue.facilityType(address(facility)), VAULT);
        assertEq(venue.factoryOf(address(facility)), address(factory));
    }

    function testRegisterPurpose() public {
        _map(GAME, FacilityCategory.PURPOSE);
        _setRegistrar(address(factory), FacilityCategory.PURPOSE);
        MockFacility facility = _createRegisteredFacility(GAME, projectOwner);
        assertTrue(venue.isFacilityOfCategory(address(facility), FacilityCategory.PURPOSE));
        assertEq(venue.facilityType(address(facility)), GAME);
    }

    function testSameKindFacilitiesShareCodehash() public {
        _setupCustody();
        MockFacility first = _createFacility(VAULT, projectOwner);
        MockFacility second = _createFacility(VAULT, address(0x1234));

        assertEq(address(first).codehash, address(second).codehash);
        assertEq(factory.codehashOf(VAULT), address(first).codehash);

        vm.prank(address(factory));
        venue.registerFacility(address(first), VAULT);
        vm.prank(address(factory));
        venue.registerFacility(address(second), VAULT);
        assertTrue(venue.isFacility(address(first)));
        assertTrue(venue.isFacility(address(second)));
    }

    function testRegisterCustodyFactoryMismatch() public {
        _map(VAULT, FacilityCategory.CUSTODY);
        _setRegistrar(address(this), FacilityCategory.CUSTODY);
        MockFacility facility = _createFacility(VAULT, projectOwner);

        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticVenueRegistry.FactoryMismatch.selector, address(facility), address(this), address(factory)
            )
        );
        venue.registerFacility(address(facility), VAULT);
    }

    function testRegisterCustodyTypeMismatch() public {
        _setupCustody();
        MockFacility facility = _createFacility(VAULT, projectOwner);

        vm.prank(address(factory));
        vm.expectRevert(
            abi.encodeWithSelector(AgenticVenueRegistry.FacilityTypeMismatch.selector, address(facility), LAUNCH, VAULT)
        );
        venue.registerFacility(address(facility), LAUNCH);
    }

    function testRegisterCustodyRejectsProxyCodehash() public {
        _setupCustody();
        // Create a real template facility so the factory reports the canonical codehash.
        _createFacility(VAULT, projectOwner);
        bytes32 expected = factory.codehashOf(VAULT);

        MockProxyFacility proxy = new MockProxyFacility(address(factory), VAULT, projectOwner);
        vm.prank(address(factory));
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticVenueRegistry.CodehashMismatch.selector, address(proxy), expected, address(proxy).codehash
            )
        );
        venue.registerFacility(address(proxy), VAULT);
    }

    function testRegisterCustodyRejectsZeroFactoryCodehash() public {
        _setupCustody();
        MockFacility facility = _createFacility(VAULT, projectOwner);
        factory.setCodehashForTest(VAULT, bytes32(0));

        vm.prank(address(factory));
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticVenueRegistry.CodehashMismatch.selector,
                address(facility),
                bytes32(0),
                address(facility).codehash
            )
        );
        venue.registerFacility(address(facility), VAULT);
    }

    // ------------------------------------------------------------------ revoke

    function testRevokeOnlyGovernance() public {
        _map(TREASURY, FacilityCategory.FEE_RECIPIENT);
        _setRegistrar(address(this), FacilityCategory.FEE_RECIPIENT);
        MockVenueAccount account = _registerTrusted(TREASURY);

        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonGov));
        venue.revokeFacility(address(account));
    }

    function testRevokeUnregistered() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticVenueRegistry.FacilityNotRegistered.selector, nonGov));
        venue.revokeFacility(nonGov);
    }

    function testRevokePOOLReverts() public {
        _map(POOL, FacilityCategory.POOL);
        _setRegistrar(address(this), FacilityCategory.POOL);
        MockVenueAccount account = _registerTrusted(POOL);

        vm.expectRevert(NonRevocableFacility.selector);
        venue.revokeFacility(address(account));
    }

    function testRevokeLPManagerReverts() public {
        _map(NPM, FacilityCategory.LP_MANAGER);
        _setRegistrar(address(this), FacilityCategory.LP_MANAGER);
        MockVenueAccount account = _registerTrusted(NPM);

        vm.expectRevert(NonRevocableFacility.selector);
        venue.revokeFacility(address(account));
    }

    function testRevokeFEERecipient() public {
        _map(TREASURY, FacilityCategory.FEE_RECIPIENT);
        _setRegistrar(address(this), FacilityCategory.FEE_RECIPIENT);
        MockVenueAccount account = _registerTrusted(TREASURY);

        vm.expectEmit(true, true, false, false, address(venue));
        emit FacilityRevoked(address(account), TREASURY);
        venue.revokeFacility(address(account));

        _assertRevokedMetadata(address(account), TREASURY, FacilityCategory.FEE_RECIPIENT, address(this));
    }

    function testRevokeCustodyKeepsMetadata() public {
        _setupCustody();
        MockFacility facility = _createRegisteredFacility(VAULT, projectOwner);

        vm.expectEmit(true, true, false, false, address(venue));
        emit FacilityRevoked(address(facility), VAULT);
        venue.revokeFacility(address(facility));

        _assertRevokedMetadata(address(facility), VAULT, FacilityCategory.CUSTODY, address(factory));
        assertFalse(venue.isFacilityOfType(address(facility), VAULT));
        assertFalse(venue.isFacilityOfCategory(address(facility), FacilityCategory.CUSTODY));
    }

    function testRevokePurpose() public {
        _map(GAME, FacilityCategory.PURPOSE);
        _setRegistrar(address(factory), FacilityCategory.PURPOSE);
        MockFacility facility = _createRegisteredFacility(GAME, projectOwner);

        venue.revokeFacility(address(facility));
        _assertRevokedMetadata(address(facility), GAME, FacilityCategory.PURPOSE, address(factory));
    }

    function testRevokeTwiceReverts() public {
        _map(TREASURY, FacilityCategory.FEE_RECIPIENT);
        _setRegistrar(address(this), FacilityCategory.FEE_RECIPIENT);
        MockVenueAccount account = _registerTrusted(TREASURY);
        venue.revokeFacility(address(account));

        vm.expectRevert(abi.encodeWithSelector(AgenticVenueRegistry.FacilityNotActive.selector, address(account)));
        venue.revokeFacility(address(account));
    }

    function testRevokedFacilityCannotBeRegisteredAgain() public {
        _map(TREASURY, FacilityCategory.FEE_RECIPIENT);
        _setRegistrar(address(this), FacilityCategory.FEE_RECIPIENT);
        MockVenueAccount account = _registerTrusted(TREASURY);
        venue.revokeFacility(address(account));

        vm.expectRevert(
            abi.encodeWithSelector(AgenticVenueRegistry.FacilityAlreadyRegistered.selector, address(account))
        );
        venue.registerFacility(address(account), TREASURY);
    }

    function _assertRevokedMetadata(address account, bytes32 kind, FacilityCategory category, address factory_)
        internal
        view
    {
        assertFalse(venue.isFacility(account));
        assertTrue(venue.isRevokedFacility(account));
        assertEq(venue.facilityType(account), kind);
        assertEq(uint256(venue.facilityCategory(account)), uint256(category));
        assertEq(venue.factoryOf(account), factory_);
    }

    // -------------------------------------------------------------- replacement

    function testSetReplacementNotApplicablePOOL() public {
        _map(POOL, FacilityCategory.POOL);
        _setRegistrar(address(this), FacilityCategory.POOL);
        MockVenueAccount account = _registerTrusted(POOL);

        vm.expectRevert(
            abi.encodeWithSelector(AgenticVenueRegistry.ReplacementNotApplicable.selector, address(account))
        );
        venue.setReplacement(address(account), address(account));
    }

    function testSetReplacementNotApplicableLPManager() public {
        _map(NPM, FacilityCategory.LP_MANAGER);
        _setRegistrar(address(this), FacilityCategory.LP_MANAGER);
        MockVenueAccount account = _registerTrusted(NPM);

        vm.expectRevert(
            abi.encodeWithSelector(AgenticVenueRegistry.ReplacementNotApplicable.selector, address(account))
        );
        venue.setReplacement(address(account), address(account));
    }

    function testSetReplacementUnregistered() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticVenueRegistry.FacilityNotRegistered.selector, nonGov));
        venue.setReplacement(nonGov, projectOwner);
    }

    function testSetReplacementCustodyOwner() public {
        _setupCustody();
        MockFacility first = _createRegisteredFacility(VAULT, projectOwner);
        MockFacility second = _createRegisteredFacility(VAULT, projectOwner);
        venue.revokeFacility(address(first));

        vm.expectEmit(true, true, false, false, address(venue));
        emit ReplacementSet(address(first), address(second));
        vm.prank(projectOwner);
        venue.setReplacement(address(first), address(second));

        assertEq(venue.replacementOf(address(first)), address(second));
    }

    function testSetReplacementCustodyOwnerOnly() public {
        _setupCustody();
        MockFacility first = _createRegisteredFacility(VAULT, projectOwner);
        MockFacility second = _createRegisteredFacility(VAULT, projectOwner);

        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(AgenticVenueRegistry.FacilityNotOwner.selector, address(first), nonGov));
        venue.setReplacement(address(first), address(second));
    }

    function testGovernanceCannotRedirectCustodyReplacement() public {
        _setupCustody();
        MockFacility first = _createRegisteredFacility(VAULT, projectOwner);
        MockFacility second = _createRegisteredFacility(VAULT, projectOwner);

        vm.expectRevert(
            abi.encodeWithSelector(AgenticVenueRegistry.FacilityNotOwner.selector, address(first), address(this))
        );
        venue.setReplacement(address(first), address(second));
    }

    function testSetReplacementCustodyWrongCategory() public {
        _setupCustody();
        _map(GAME, FacilityCategory.PURPOSE);
        _setRegistrar(address(factory), FacilityCategory.PURPOSE);

        MockFacility custody = _createRegisteredFacility(VAULT, projectOwner);
        MockFacility purpose = _createRegisteredFacility(GAME, projectOwner);

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticVenueRegistry.ReplacementCategoryMismatch.selector,
                address(purpose),
                FacilityCategory.CUSTODY,
                FacilityCategory.PURPOSE
            )
        );
        venue.setReplacement(address(custody), address(purpose));
    }

    function testSetReplacementCustodyWrongSubtype() public {
        _setupCustody();
        MockFacility vault_ = _createRegisteredFacility(VAULT, projectOwner);
        MockFacility launch_ = _createRegisteredFacility(LAUNCH, projectOwner);

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticVenueRegistry.ReplacementTypeMismatch.selector, address(launch_), VAULT, LAUNCH
            )
        );
        venue.setReplacement(address(vault_), address(launch_));
    }

    function testSetReplacementMustBeActive() public {
        _setupCustody();
        MockFacility first = _createRegisteredFacility(VAULT, projectOwner);
        MockFacility second = _createRegisteredFacility(VAULT, projectOwner);
        venue.revokeFacility(address(second));

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticVenueRegistry.ReplacementNotActive.selector, address(second)));
        venue.setReplacement(address(first), address(second));
    }

    function testSetReplacementNotSelf() public {
        _setupCustody();
        MockFacility first = _createRegisteredFacility(VAULT, projectOwner);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticVenueRegistry.ReplacementIsSelf.selector, address(first)));
        venue.setReplacement(address(first), address(first));
    }

    function testSetReplacementZero() public {
        _setupCustody();
        MockFacility first = _createRegisteredFacility(VAULT, projectOwner);

        vm.prank(projectOwner);
        vm.expectRevert(AgenticVenueRegistry.ZeroReplacement.selector);
        venue.setReplacement(address(first), address(0));
    }

    function testSetReplacementCanBeUpdatedByOwner() public {
        _setupCustody();
        MockFacility first = _createRegisteredFacility(VAULT, projectOwner);
        MockFacility second = _createRegisteredFacility(VAULT, projectOwner);
        MockFacility third = _createRegisteredFacility(VAULT, projectOwner);

        vm.prank(projectOwner);
        venue.setReplacement(address(first), address(second));
        vm.prank(projectOwner);
        venue.setReplacement(address(first), address(third));
        assertEq(venue.replacementOf(address(first)), address(third));
    }

    function testSetReplacementPurposeOwner() public {
        _map(GAME, FacilityCategory.PURPOSE);
        _setRegistrar(address(factory), FacilityCategory.PURPOSE);
        MockFacility first = _createRegisteredFacility(GAME, projectOwner);
        MockFacility second = _createRegisteredFacility(GAME, projectOwner);

        vm.prank(projectOwner);
        venue.setReplacement(address(first), address(second));
        assertEq(venue.replacementOf(address(first)), address(second));
    }

    function testSetReplacementFEEGovernance() public {
        _map(TREASURY, FacilityCategory.FEE_RECIPIENT);
        _setRegistrar(address(this), FacilityCategory.FEE_RECIPIENT);
        MockVenueAccount first = _registerTrusted(TREASURY);
        MockVenueAccount second = _registerTrusted(TREASURY);
        venue.revokeFacility(address(first));

        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonGov));
        venue.setReplacement(address(first), address(second));

        vm.expectEmit(true, true, false, false, address(venue));
        emit ReplacementSet(address(first), address(second));
        venue.setReplacement(address(first), address(second));
        assertEq(venue.replacementOf(address(first)), address(second));
    }

    function testSetReplacementFEEWrongSubtype() public {
        _map(TREASURY, FacilityCategory.FEE_RECIPIENT);
        _map(OTHER_TREASURY, FacilityCategory.FEE_RECIPIENT);
        _setRegistrar(address(this), FacilityCategory.FEE_RECIPIENT);
        MockVenueAccount first = _registerTrusted(TREASURY);
        MockVenueAccount second = _registerTrusted(OTHER_TREASURY);

        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticVenueRegistry.ReplacementTypeMismatch.selector, address(second), TREASURY, OTHER_TREASURY
            )
        );
        venue.setReplacement(address(first), address(second));
    }

    function testSetReplacementFEEUsesGovernanceNotOwner() public {
        // FEE_RECIPIENT accounts need not implement IFacility; governance path must
        // not call owner().
        _map(TREASURY, FacilityCategory.FEE_RECIPIENT);
        _setRegistrar(address(this), FacilityCategory.FEE_RECIPIENT);
        MockVenueAccount first = _registerTrusted(TREASURY);
        MockVenueAccount second = _registerTrusted(TREASURY);

        venue.setReplacement(address(first), address(second));
        assertEq(venue.replacementOf(address(first)), address(second));
    }

    // --------------------------------------------------------------- governance

    function testGovernanceTwoStep() public {
        address newGov = address(0xC0FFEE);

        vm.expectEmit(true, true, false, true, address(venue));
        emit GovernanceTransferStarted(address(this), newGov);
        venue.transferGovernance(newGov);

        vm.prank(newGov);
        venue.acceptGovernance();
        assertEq(venue.governance(), newGov);
        assertEq(venue.pendingGovernance(), address(0));

        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, address(this)));
        venue.addTypeCategory(POOL, FacilityCategory.POOL);

        vm.prank(newGov);
        venue.addTypeCategory(POOL, FacilityCategory.POOL);
        assertEq(uint256(venue.categoryOfType(POOL)), uint256(FacilityCategory.POOL));
    }

    function testTransferGovernanceOnlyGovernance() public {
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotGovernance.selector, nonGov));
        venue.transferGovernance(nonGov);
    }

    function testAcceptGovernanceOnlyPending() public {
        vm.prank(nonGov);
        vm.expectRevert(abi.encodeWithSelector(Governance2Step.NotPendingGovernance.selector, nonGov));
        venue.acceptGovernance();
    }
}
