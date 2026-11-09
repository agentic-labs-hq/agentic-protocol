// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {AgenticNFTFacilityBase} from "../../contracts/facility/AgenticNFTFacilityBase.sol";
import {AgenticNFTFacilityFactory} from "../../contracts/facility/AgenticNFTFacilityFactory.sol";
import {AgenticNFTEscrowFacility} from "../../contracts/facility/AgenticNFTEscrowFacility.sol";
import {AgenticNFTGameFacility} from "../../contracts/facility/AgenticNFTGameFacility.sol";
import {AgenticNFTLaunchFacility} from "../../contracts/facility/AgenticNFTLaunchFacility.sol";
import {AgenticNFTLockerFacility} from "../../contracts/facility/AgenticNFTLockerFacility.sol";
import {AgenticNFTVaultFacility} from "../../contracts/facility/AgenticNFTVaultFacility.sol";
import {AgenticNFT} from "../../contracts/token/AgenticNFT.sol";

import {MockTransferPolicy} from "../mocks/MockTransferPolicy.sol";
import {NFTFacilityFixture} from "../helpers/NFTFacilityFixture.sol";

contract AgenticNFTFacilitiesTest is NFTFacilityFixture {
    AgenticNFT internal nft;

    AgenticNFTVaultFacility internal nftVault;
    AgenticNFTLaunchFacility internal launch;
    AgenticNFTLockerFacility internal locker;
    AgenticNFTGameFacility internal nftGame;
    AgenticNFTEscrowFacility internal escrow;

    event NFTReleased(address indexed collection, uint256 indexed tokenId, address indexed to);
    event NFTRefunded(address indexed collection, uint256 indexed tokenId, address indexed to);
    event NFTConsumed(address indexed collection, uint256 indexed tokenId);
    event NFTUnlocked(address indexed collection, uint256 indexed tokenId, address indexed to);

    function setUp() public {
        _deployNFTFacilities();
        nft = _createNFTCollection();
        nftVault = _defaultNFTVault();
        launch = _defaultNFTLaunch();
        locker = _defaultNFTLocker();
        nftGame = _defaultNFTGame();
        escrow = _defaultNFTEscrow();
    }

    // ------------------------------------------------------------ NFT_VAULT

    function testNFTVaultReleaseOwnerToAgent() public {
        uint256 tokenId = _mintNFT(nft, address(nftVault));

        vm.expectEmit(true, true, true, true, address(nftVault));
        emit NFTReleased(address(nft), tokenId, agent);
        vm.prank(projectOwner);
        nftVault.release(address(nft), tokenId, agent);

        assertEq(nft.ownerOf(tokenId), agent);
        assertEq(nft.balanceOf(address(nftVault)), 0);
    }

    function testNFTVaultReleaseOnlyOwner() public {
        uint256 tokenId = _mintNFT(nft, address(nftVault));

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotOwner.selector, agent));
        nftVault.release(address(nft), tokenId, agent);

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotOwner.selector, nonAgent));
        nftVault.release(address(nft), tokenId, agent);

        vm.prank(address(nftVault));
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotOwner.selector, address(nftVault)));
        nftVault.release(address(nft), tokenId, agent);
    }

    function testNFTVaultReleaseRejectsNonAgentRecipient() public {
        uint256 tokenId = _mintNFT(nft, address(nftVault));

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.GatedRecipientNotAgent.selector, nonAgent));
        nftVault.release(address(nft), tokenId, nonAgent);
    }

    function testNFTVaultReleaseRejectsFacilityRecipient() public {
        AgenticNFTVaultFacility other = _createNFTVault(projectOwner);
        uint256 tokenId = _mintNFT(nft, address(nftVault));

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTFacilityBase.FacilityRecipientNotAllowed.selector, address(other))
        );
        nftVault.release(address(nft), tokenId, address(other));
    }

    function testNFTVaultReleaseRejectsZeroRecipient() public {
        uint256 tokenId = _mintNFT(nft, address(nftVault));

        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTFacilityBase.ZeroRecipient.selector);
        nftVault.release(address(nft), tokenId, address(0));
    }

    function testNFTVaultReleaseRejectsNonexistentToken() public {
        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotHeld.selector, address(nft), 999));
        nftVault.release(address(nft), 999, agent);
    }

    function testNFTVaultReleaseRejectsNotHeldToken() public {
        uint256 tokenId = _mintNFT(nft, agent);
        uint256 missing = _mintNFT(nft, address(nftVault));

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotHeld.selector, address(nft), tokenId));
        nftVault.release(address(nft), tokenId, agent2);

        vm.prank(projectOwner);
        nftVault.release(address(nft), missing, agent2);
        assertEq(nft.ownerOf(missing), agent2);
    }

    function testNFTVaultNonGatedCollectionAllowsAnyNonZeroRecipient() public {
        MockTransferPolicy permissive = new MockTransferPolicy();
        permissive.setPermissive(true);
        AgenticNFT plain = _createNFTCollectionWithPolicy(address(permissive), false);
        uint256 tokenId = _mintNFT(plain, address(nftVault));

        vm.prank(projectOwner);
        nftVault.release(address(plain), tokenId, nonAgent);

        assertEq(plain.ownerOf(tokenId), nonAgent);
    }

    function testNFTVaultNonGatedCollectionStillRejectsZeroRecipient() public {
        MockTransferPolicy permissive = new MockTransferPolicy();
        permissive.setPermissive(true);
        AgenticNFT plain = _createNFTCollectionWithPolicy(address(permissive), false);
        uint256 tokenId = _mintNFT(plain, address(nftVault));

        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTFacilityBase.ZeroRecipient.selector);
        nftVault.release(address(plain), tokenId, address(0));
    }

    function testNFTVaultTwoStepOwnership() public {
        uint256 tokenId = _mintNFT(nft, address(nftVault));

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotOwner.selector, agent));
        nftVault.transferOwnership(agent);

        vm.prank(projectOwner);
        nftVault.transferOwnership(agent);
        assertEq(nftVault.pendingOwner(), agent);
        assertEq(nftVault.owner(), projectOwner);

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotPendingOwner.selector, nonAgent));
        nftVault.acceptOwnership();

        vm.prank(agent);
        nftVault.acceptOwnership();
        assertEq(nftVault.owner(), agent);
        assertEq(nftVault.pendingOwner(), address(0));

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotOwner.selector, projectOwner));
        nftVault.release(address(nft), tokenId, agent2);

        vm.prank(agent);
        nftVault.release(address(nft), tokenId, agent2);
        assertEq(nft.ownerOf(tokenId), agent2);
    }

    function testNFTVaultTransferOwnershipRejectsZero() public {
        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTFacilityBase.ZeroAddress.selector);
        nftVault.transferOwnership(address(0));
    }

    function testNFTFacilityOnERC721ReceivedReturnsSelector() public view {
        bytes4 selector = nftVault.onERC721Received(address(0), address(0), 0, "");
        assertEq(selector, IERC721Receiver.onERC721Received.selector);
    }

    // ----------------------------------------------------------- NFT_LAUNCH

    function testNFTLaunchOperatorReleaseToAgentBuyer() public {
        uint256 tokenId = _mintNFT(nft, address(launch));

        vm.expectEmit(true, true, true, true, address(launch));
        emit NFTReleased(address(nft), tokenId, agent2);
        vm.prank(projectOwner);
        launch.release(address(nft), tokenId, agent2);

        assertEq(nft.ownerOf(tokenId), agent2);
        assertEq(nft.balanceOf(address(launch)), 0);
    }

    function testNFTLaunchReleaseOnlyOperator() public {
        AgenticNFTLaunchFacility op = _createNFTLaunch(projectOwner, agent2, agent);
        uint256 tokenId = _mintNFT(nft, address(op));

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTLaunchFacility.NotOperator.selector, projectOwner));
        op.release(address(nft), tokenId, agent);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTLaunchFacility.NotOperator.selector, agent));
        op.release(address(nft), tokenId, agent);

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTLaunchFacility.NotOperator.selector, nonAgent));
        op.release(address(nft), tokenId, agent);
    }

    function testNFTLaunchReleaseAfterCloseOnlyBeneficiary() public {
        uint256 tokenId = _mintNFT(nft, address(launch));
        uint256 tokenId2 = _mintNFT(nft, address(launch));

        vm.prank(projectOwner);
        launch.close();

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTLaunchFacility.ClosedRecipientNotBeneficiary.selector, agent2));
        launch.release(address(nft), tokenId, agent2);

        vm.prank(projectOwner);
        launch.release(address(nft), tokenId2, agent);
        assertEq(nft.ownerOf(tokenId2), agent);
    }

    function testNFTLaunchCloseRequiresBeneficiary() public {
        AgenticNFTLaunchFacility op = _createNFTLaunch(projectOwner, projectOwner, address(0));

        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTLaunchFacility.BeneficiaryNotSet.selector);
        op.close();
    }

    function testNFTLaunchCloseOnlyOwnerOrOperator() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTLaunchFacility.NotOwnerOrOperator.selector, agent));
        launch.close();

        vm.prank(projectOwner);
        launch.close();
        assertTrue(launch.closed());

        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTLaunchFacility.AlreadyClosed.selector);
        launch.close();
    }

    function testNFTLaunchOperatorCanClose() public {
        AgenticNFTLaunchFacility op = _createNFTLaunch(projectOwner, agent2, agent);

        vm.prank(agent2);
        op.close();
        assertTrue(op.closed());
    }

    function testNFTLaunchSetOperatorOnlyOwner() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotOwner.selector, agent));
        launch.setOperator(agent2);

        vm.prank(projectOwner);
        launch.setOperator(agent2);
        assertEq(launch.operator(), agent2);

        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTLaunchFacility.ZeroOperator.selector);
        launch.setOperator(address(0));
    }

    function testNFTLaunchSetBeneficiaryAgentOnly() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotOwner.selector, agent));
        launch.setBeneficiary(agent2);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotAgent.selector, nonAgent));
        launch.setBeneficiary(nonAgent);

        AgenticNFTVaultFacility other = _createNFTVault(projectOwner);
        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.FacilityNotAgent.selector, address(other)));
        launch.setBeneficiary(address(other));

        vm.prank(projectOwner);
        launch.setBeneficiary(agent2);
        assertEq(launch.beneficiary(), agent2);

        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTLaunchFacility.ZeroBeneficiary.selector);
        launch.setBeneficiary(address(0));
    }

    function testNFTLaunchCreationRejectsNonAgentBeneficiary() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.AgentRequired.selector, nonAgent));
        _createNFTLaunch(projectOwner, projectOwner, nonAgent);
    }

    function testNFTLaunchCreationRejectsFacilityBeneficiary() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.FacilityNotAgent.selector, address(nftVault)));
        _createNFTLaunch(projectOwner, projectOwner, address(nftVault));
    }

    function testNFTLaunchReleaseRejectsNonAgentAndFacility() public {
        uint256 tokenId = _mintNFT(nft, address(launch));
        AgenticNFTVaultFacility other = _createNFTVault(projectOwner);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.GatedRecipientNotAgent.selector, nonAgent));
        launch.release(address(nft), tokenId, nonAgent);

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTFacilityBase.FacilityRecipientNotAllowed.selector, address(other))
        );
        launch.release(address(nft), tokenId, address(other));
    }

    function testNFTLaunchReleaseRejectsNotHeldToken() public {
        uint256 tokenId = _mintNFT(nft, agent);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotHeld.selector, address(nft), tokenId));
        launch.release(address(nft), tokenId, agent2);
    }

    function testNFTLaunchZeroOperatorCanBeSetLater() public {
        AgenticNFTLaunchFacility op = _createNFTLaunch(projectOwner, address(0), agent);
        uint256 tokenId = _mintNFT(nft, address(op));

        vm.prank(projectOwner);
        op.setOperator(projectOwner);

        vm.prank(projectOwner);
        op.release(address(nft), tokenId, agent);
        assertEq(nft.ownerOf(tokenId), agent);
    }

    // ----------------------------------------------------------- NFT_LOCKER

    function testNFTLockerUnlockBeforeTimeReverts() public {
        uint256 tokenId = _mintNFT(nft, address(locker));

        vm.prank(nonAgent);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTLockerFacility.UnlockTimeNotReached.selector, DEFAULT_UNLOCK_TIME)
        );
        locker.unlock(address(nft), tokenId, agent);
    }

    function testNFTLockerUnlockAfterTimeAnyoneToBeneficiary() public {
        uint256 tokenId = _mintNFT(nft, address(locker));

        vm.warp(DEFAULT_UNLOCK_TIME);
        vm.expectEmit(true, true, true, true, address(locker));
        emit NFTUnlocked(address(nft), tokenId, agent);
        vm.prank(nonAgent);
        locker.unlock(address(nft), tokenId, agent);

        assertEq(nft.ownerOf(tokenId), agent);
        assertEq(nft.balanceOf(address(locker)), 0);
    }

    function testNFTLockerUnlockRejectsOtherRecipient() public {
        uint256 tokenId = _mintNFT(nft, address(locker));
        vm.warp(DEFAULT_UNLOCK_TIME);

        vm.prank(nonAgent);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTLockerFacility.UnlockRecipientNotBeneficiary.selector, agent2, agent)
        );
        locker.unlock(address(nft), tokenId, agent2);

        vm.prank(nonAgent);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTLockerFacility.UnlockRecipientNotBeneficiary.selector, nonAgent, agent)
        );
        locker.unlock(address(nft), tokenId, nonAgent);

        vm.prank(nonAgent);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTLockerFacility.UnlockRecipientNotBeneficiary.selector, address(0), agent)
        );
        locker.unlock(address(nft), tokenId, address(0));
    }

    function testNFTLockerUnlockRejectsNotHeldToken() public {
        uint256 tokenId = _mintNFT(nft, agent);
        vm.warp(DEFAULT_UNLOCK_TIME);

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotHeld.selector, address(nft), tokenId));
        locker.unlock(address(nft), tokenId, agent);
    }

    function testNFTLockerReleaseAlwaysReverts() public {
        uint256 tokenId = _mintNFT(nft, address(locker));

        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTLockerFacility.ReleaseNotSupported.selector);
        locker.release(address(nft), tokenId, agent);
    }

    function testNFTLockerExtendOnlyOwnerAndOnlyIncreases() public {
        uint256 tokenId = _mintNFT(nft, address(locker));

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotOwner.selector, agent));
        locker.extend(DEFAULT_UNLOCK_TIME + 1);

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticNFTLockerFacility.UnlockTimeNotExtended.selector, DEFAULT_UNLOCK_TIME, DEFAULT_UNLOCK_TIME
            )
        );
        locker.extend(DEFAULT_UNLOCK_TIME);

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticNFTLockerFacility.UnlockTimeNotExtended.selector, DEFAULT_UNLOCK_TIME, DEFAULT_UNLOCK_TIME - 1
            )
        );
        locker.extend(DEFAULT_UNLOCK_TIME - 1);

        uint64 extended = DEFAULT_UNLOCK_TIME + 1_000;
        vm.prank(projectOwner);
        locker.extend(extended);
        assertEq(locker.unlockTime(), extended);

        vm.warp(DEFAULT_UNLOCK_TIME);
        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTLockerFacility.UnlockTimeNotReached.selector, extended));
        locker.unlock(address(nft), tokenId, agent);

        vm.warp(extended);
        vm.prank(nonAgent);
        locker.unlock(address(nft), tokenId, agent);
        assertEq(nft.ownerOf(tokenId), agent);
    }

    function testNFTLockerExtendAfterUnlockReverts() public {
        vm.warp(DEFAULT_UNLOCK_TIME);

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTLockerFacility.UnlockTimeReached.selector, DEFAULT_UNLOCK_TIME)
        );
        locker.extend(DEFAULT_UNLOCK_TIME + 1);
    }

    function testNFTLockerSetBeneficiaryBeforeUnlock() public {
        uint256 tokenId = _mintNFT(nft, address(locker));

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotOwner.selector, agent));
        locker.setBeneficiary(agent2);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotAgent.selector, nonAgent));
        locker.setBeneficiary(nonAgent);

        AgenticNFTVaultFacility other = _createNFTVault(projectOwner);
        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.FacilityNotAgent.selector, address(other)));
        locker.setBeneficiary(address(other));

        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTLockerFacility.ZeroBeneficiary.selector);
        locker.setBeneficiary(address(0));

        vm.prank(projectOwner);
        locker.setBeneficiary(agent2);
        assertEq(locker.beneficiary(), agent2);

        vm.warp(DEFAULT_UNLOCK_TIME);
        vm.prank(nonAgent);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTLockerFacility.UnlockRecipientNotBeneficiary.selector, agent, agent2)
        );
        locker.unlock(address(nft), tokenId, agent);

        vm.prank(nonAgent);
        locker.unlock(address(nft), tokenId, agent2);
        assertEq(nft.ownerOf(tokenId), agent2);
    }

    function testNFTLockerSetBeneficiaryAfterUnlockReverts() public {
        vm.warp(DEFAULT_UNLOCK_TIME);

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTLockerFacility.UnlockTimeReached.selector, DEFAULT_UNLOCK_TIME)
        );
        locker.setBeneficiary(agent2);
    }

    function testNFTLockerZeroBeneficiaryRejected() public {
        vm.expectRevert(AgenticNFTFacilityFactory.LockerBeneficiaryRequired.selector);
        _createNFTLocker(projectOwner, address(0), DEFAULT_UNLOCK_TIME);
    }

    function testNFTLockerCreationRejectsNonAgentBeneficiary() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.AgentRequired.selector, nonAgent));
        _createNFTLocker(projectOwner, nonAgent, DEFAULT_UNLOCK_TIME);
    }

    // ------------------------------------------------------------- NFT_GAME

    function testNFTGameAgentDepositViaSafeTransfer() public {
        uint256 tokenId = _mintNFT(nft, agent);

        vm.prank(agent);
        nft.safeTransferFrom(agent, address(nftGame), tokenId);

        assertEq(nft.ownerOf(tokenId), address(nftGame));
    }

    function testNFTGameOperatorReleaseToAgent() public {
        uint256 tokenId = _mintNFT(nft, agent);
        _depositNFT(nft, address(nftGame), tokenId);

        vm.expectEmit(true, true, true, true, address(nftGame));
        emit NFTReleased(address(nft), tokenId, agent2);
        vm.prank(projectOwner);
        nftGame.release(address(nft), tokenId, agent2);

        assertEq(nft.ownerOf(tokenId), agent2);
        assertEq(nft.balanceOf(address(nftGame)), 0);
    }

    function testNFTGameOperatorRefundToAgent() public {
        uint256 tokenId = _mintNFT(nft, agent);
        _depositNFT(nft, address(nftGame), tokenId);

        vm.expectEmit(true, true, true, true, address(nftGame));
        emit NFTRefunded(address(nft), tokenId, agent);
        vm.prank(projectOwner);
        nftGame.refund(address(nft), tokenId, agent);

        assertEq(nft.ownerOf(tokenId), agent);
    }

    function testNFTGameConsumeLocksToken() public {
        uint256 tokenId = _mintNFT(nft, agent);
        _depositNFT(nft, address(nftGame), tokenId);

        vm.expectEmit(true, true, true, true, address(nftGame));
        emit NFTConsumed(address(nft), tokenId);
        vm.prank(projectOwner);
        nftGame.consume(address(nft), tokenId);

        assertTrue(nftGame.consumed(address(nft), tokenId));
        assertEq(nft.ownerOf(tokenId), address(nftGame));

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTGameFacility.TokenConsumed.selector, address(nft), tokenId));
        nftGame.release(address(nft), tokenId, agent);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTGameFacility.TokenConsumed.selector, address(nft), tokenId));
        nftGame.refund(address(nft), tokenId, agent);
    }

    function testNFTGameConsumeTwiceReverts() public {
        uint256 tokenId = _mintNFT(nft, agent);
        _depositNFT(nft, address(nftGame), tokenId);

        vm.startPrank(projectOwner);
        nftGame.consume(address(nft), tokenId);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTGameFacility.TokenConsumed.selector, address(nft), tokenId));
        nftGame.consume(address(nft), tokenId);
        vm.stopPrank();
    }

    function testNFTGameConsumeRejectsNotHeldToken() public {
        uint256 tokenId = _mintNFT(nft, agent);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotHeld.selector, address(nft), tokenId));
        nftGame.consume(address(nft), tokenId);
    }

    function testNFTGameOnlyOperatorCanAct() public {
        uint256 tokenId = _mintNFT(nft, agent);
        _depositNFT(nft, address(nftGame), tokenId);

        vm.startPrank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTGameFacility.NotOperator.selector, agent));
        nftGame.consume(address(nft), tokenId);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTGameFacility.NotOperator.selector, agent));
        nftGame.release(address(nft), tokenId, agent2);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTGameFacility.NotOperator.selector, agent));
        nftGame.refund(address(nft), tokenId, agent2);
        vm.stopPrank();
    }

    function testNFTGameSetOperatorOnlyOwner() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotOwner.selector, agent));
        nftGame.setOperator(agent);

        vm.prank(projectOwner);
        nftGame.setOperator(agent2);
        assertEq(nftGame.operator(), agent2);

        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTGameFacility.ZeroOperator.selector);
        nftGame.setOperator(address(0));
    }

    function testNFTGameReleaseAndRefundRejectNonAgentAndFacility() public {
        uint256 tokenId = _mintNFT(nft, agent);
        _depositNFT(nft, address(nftGame), tokenId);
        AgenticNFTVaultFacility other = _createNFTVault(projectOwner);

        vm.startPrank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.GatedRecipientNotAgent.selector, nonAgent));
        nftGame.release(address(nft), tokenId, nonAgent);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTFacilityBase.FacilityRecipientNotAllowed.selector, address(other))
        );
        nftGame.release(address(nft), tokenId, address(other));
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.GatedRecipientNotAgent.selector, nonAgent));
        nftGame.refund(address(nft), tokenId, nonAgent);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTFacilityBase.FacilityRecipientNotAllowed.selector, address(other))
        );
        nftGame.refund(address(nft), tokenId, address(other));
        vm.stopPrank();
    }

    function testNFTGameReleaseRejectsZeroRecipient() public {
        uint256 tokenId = _mintNFT(nft, agent);
        _depositNFT(nft, address(nftGame), tokenId);

        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTFacilityBase.ZeroRecipient.selector);
        nftGame.release(address(nft), tokenId, address(0));
    }

    // ----------------------------------------------------------- NFT_ESCROW

    function testNFTEscrowAgentDepositViaSafeTransfer() public {
        uint256 tokenId = _mintNFT(nft, agent);

        vm.prank(agent);
        nft.safeTransferFrom(agent, address(escrow), tokenId);

        assertEq(nft.ownerOf(tokenId), address(escrow));
    }

    function testNFTEscrowBeneficiaryRelease() public {
        uint256 tokenId = _mintNFT(nft, agent);
        _depositNFT(nft, address(escrow), tokenId);

        vm.expectEmit(true, true, true, true, address(escrow));
        emit NFTReleased(address(nft), tokenId, agent2);
        vm.prank(agent);
        escrow.release(address(nft), tokenId, agent2);

        assertEq(nft.ownerOf(tokenId), agent2);
    }

    function testNFTEscrowArbiterRelease() public {
        uint256 tokenId = _mintNFT(nft, agent);
        _depositNFT(nft, address(escrow), tokenId);

        vm.prank(projectOwner);
        escrow.release(address(nft), tokenId, agent2);

        assertEq(nft.ownerOf(tokenId), agent2);
    }

    function testNFTEscrowArbiterRefund() public {
        uint256 tokenId = _mintNFT(nft, agent);
        _depositNFT(nft, address(escrow), tokenId);

        vm.expectEmit(true, true, true, true, address(escrow));
        emit NFTRefunded(address(nft), tokenId, agent);
        vm.prank(projectOwner);
        escrow.refund(address(nft), tokenId, agent);

        assertEq(nft.ownerOf(tokenId), agent);
    }

    function testNFTEscrowReleaseSettlesOnce() public {
        uint256 tokenId = _mintNFT(nft, agent);
        _depositNFT(nft, address(escrow), tokenId);

        vm.prank(agent);
        escrow.release(address(nft), tokenId, agent2);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotHeld.selector, address(nft), tokenId));
        escrow.refund(address(nft), tokenId, agent);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotHeld.selector, address(nft), tokenId));
        escrow.release(address(nft), tokenId, agent);
    }

    function testNFTEscrowRefundSettlesOnce() public {
        uint256 tokenId = _mintNFT(nft, agent);
        _depositNFT(nft, address(escrow), tokenId);

        vm.prank(projectOwner);
        escrow.refund(address(nft), tokenId, agent);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotHeld.selector, address(nft), tokenId));
        escrow.refund(address(nft), tokenId, agent);
    }

    function testNFTEscrowWrongRoleRelease() public {
        uint256 tokenId = _mintNFT(nft, agent);
        _depositNFT(nft, address(escrow), tokenId);

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTEscrowFacility.NotBeneficiaryOrArbiter.selector, nonAgent));
        escrow.release(address(nft), tokenId, agent2);

        vm.prank(agent2);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTEscrowFacility.NotBeneficiaryOrArbiter.selector, agent2));
        escrow.release(address(nft), tokenId, agent2);
    }

    function testNFTEscrowWrongRoleRefund() public {
        uint256 tokenId = _mintNFT(nft, agent);
        _depositNFT(nft, address(escrow), tokenId);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTEscrowFacility.NotArbiter.selector, agent));
        escrow.refund(address(nft), tokenId, agent);

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTEscrowFacility.NotArbiter.selector, nonAgent));
        escrow.refund(address(nft), tokenId, agent);
    }

    function testNFTEscrowConsumeAlwaysReverts() public {
        uint256 tokenId = _mintNFT(nft, address(escrow));

        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTEscrowFacility.ConsumeNotSupported.selector);
        escrow.consume(address(nft), tokenId);
    }

    function testNFTEscrowSetArbiterOnlyOwner() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotOwner.selector, agent));
        escrow.setArbiter(agent);

        vm.prank(projectOwner);
        escrow.setArbiter(agent2);
        assertEq(escrow.arbiter(), agent2);

        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTEscrowFacility.ZeroArbiter.selector);
        escrow.setArbiter(address(0));
    }

    function testNFTEscrowSetBeneficiaryAgentOnly() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotOwner.selector, agent));
        escrow.setBeneficiary(agent2);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotAgent.selector, nonAgent));
        escrow.setBeneficiary(nonAgent);

        AgenticNFTVaultFacility other = _createNFTVault(projectOwner);
        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.FacilityNotAgent.selector, address(other)));
        escrow.setBeneficiary(address(other));

        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTEscrowFacility.ZeroBeneficiary.selector);
        escrow.setBeneficiary(address(0));

        vm.prank(projectOwner);
        escrow.setBeneficiary(agent2);
        assertEq(escrow.beneficiary(), agent2);
    }

    function testNFTEscrowReleaseRejectsNonAgentAndFacility() public {
        uint256 tokenId = _mintNFT(nft, agent);
        _depositNFT(nft, address(escrow), tokenId);
        AgenticNFTVaultFacility other = _createNFTVault(projectOwner);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.GatedRecipientNotAgent.selector, nonAgent));
        escrow.release(address(nft), tokenId, nonAgent);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTFacilityBase.FacilityRecipientNotAllowed.selector, address(other))
        );
        escrow.release(address(nft), tokenId, address(other));
    }

    function testNFTEscrowReleaseRejectsNotHeldToken() public {
        uint256 tokenId = _mintNFT(nft, agent);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotHeld.selector, address(nft), tokenId));
        escrow.release(address(nft), tokenId, agent2);
    }

    function testNFTEscrowCreationRejectsNonAgentBeneficiary() public {
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityFactory.AgentRequired.selector, nonAgent));
        _createNFTEscrow(projectOwner, projectOwner, nonAgent);
    }

    // ------------------------------------------------------------- migration

    function testNFTMigrationRequiresRevocation() public {
        AgenticNFTVaultFacility old = _createNFTVault(projectOwner);
        AgenticNFTVaultFacility replacement = _createNFTVault(projectOwner);
        _mintNFT(nft, address(old));

        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTFacilityBase.FacilityNotRevoked.selector);
        old.migrate(address(replacement));
    }

    function testNFTMigrationRequiresRegistryReplacement() public {
        AgenticNFTVaultFacility old = _createNFTVault(projectOwner);
        AgenticNFTVaultFacility replacement = _createNFTVault(projectOwner);
        _revokeNFTFacility(address(old));

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticNFTFacilityBase.NotRegistryReplacement.selector, address(0), address(replacement)
            )
        );
        old.migrate(address(replacement));
    }

    function testNFTMigrationRejectsWrongTargetSelfAndZero() public {
        AgenticNFTVaultFacility old = _createNFTVault(projectOwner);
        AgenticNFTVaultFacility replacement = _createNFTVault(projectOwner);
        AgenticNFTVaultFacility other = _createNFTVault(projectOwner);
        _revokeNFTFacility(address(old));
        _setNFTReplacement(address(old), address(replacement));

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticNFTFacilityBase.NotRegistryReplacement.selector, address(replacement), address(other)
            )
        );
        old.migrate(address(other));

        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTFacilityBase.ReplacementIsSelf.selector);
        old.migrate(address(old));

        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTFacilityBase.ZeroAddress.selector);
        old.migrate(address(0));
    }

    function testNFTMigrationOnlyOwner() public {
        AgenticNFTVaultFacility old = _createNFTVault(projectOwner);
        AgenticNFTVaultFacility replacement = _createNFTVault(projectOwner);
        _revokeNFTFacility(address(old));
        _setNFTReplacement(address(old), address(replacement));

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotOwner.selector, agent));
        old.migrate(address(replacement));
    }

    function testNFTMigrationRejectsInactiveReplacement() public {
        AgenticNFTVaultFacility old = _createNFTVault(projectOwner);
        AgenticNFTVaultFacility replacement = _createNFTVault(projectOwner);
        _revokeNFTFacility(address(old));
        _setNFTReplacement(address(old), address(replacement));
        _revokeNFTFacility(address(replacement));

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTFacilityBase.ReplacementNotActive.selector, address(replacement))
        );
        old.migrate(address(replacement));
    }

    function testNFTMigrationSetsTargetWithoutMovingTokens() public {
        AgenticNFTVaultFacility old = _createNFTVault(projectOwner);
        AgenticNFTVaultFacility replacement = _createNFTVault(projectOwner);
        uint256 first = _mintNFT(nft, address(old));
        uint256 second = _mintNFT(nft, address(old));

        _revokeNFTFacility(address(old));
        _setNFTReplacement(address(old), address(replacement));
        _migrateNFTFacility(address(old), address(replacement));

        assertEq(old.migrationTarget(), address(replacement));
        assertEq(nft.ownerOf(first), address(old));
        assertEq(nft.ownerOf(second), address(old));
        assertEq(nft.balanceOf(address(replacement)), 0);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = first;
        tokenIds[1] = second;
        vm.prank(projectOwner);
        old.migrateTokens(address(nft), tokenIds);

        assertEq(nft.ownerOf(first), address(replacement));
        assertEq(nft.ownerOf(second), address(replacement));
        assertEq(nft.balanceOf(address(old)), 0);
        assertEq(nft.balanceOf(address(replacement)), 2);
    }

    function testNFTMigrateTokensOnlyOwner() public {
        AgenticNFTVaultFacility old = _createNFTVault(projectOwner);
        AgenticNFTVaultFacility replacement = _createNFTVault(projectOwner);
        uint256 tokenId = _mintNFT(nft, address(old));
        _revokeNFTFacility(address(old));
        _setNFTReplacement(address(old), address(replacement));
        _migrateNFTFacility(address(old), address(replacement));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotOwner.selector, agent));
        old.migrateTokens(address(nft), tokenIds);
    }

    function testNFTMigrateTokensBeforeMigrateReverts() public {
        AgenticNFTVaultFacility old = _createNFTVault(projectOwner);
        AgenticNFTVaultFacility replacement = _createNFTVault(projectOwner);
        uint256 tokenId = _mintNFT(nft, address(old));
        _revokeNFTFacility(address(old));
        _setNFTReplacement(address(old), address(replacement));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(projectOwner);
        vm.expectRevert(AgenticNFTFacilityBase.MigrationTargetNotSet.selector);
        old.migrateTokens(address(nft), tokenIds);
    }

    function testNFTMigrateTokensRejectsNotHeldToken() public {
        AgenticNFTVaultFacility old = _createNFTVault(projectOwner);
        AgenticNFTVaultFacility replacement = _createNFTVault(projectOwner);
        uint256 held = _mintNFT(nft, address(old));
        uint256 notHeld = _mintNFT(nft, agent);
        _revokeNFTFacility(address(old));
        _setNFTReplacement(address(old), address(replacement));
        _migrateNFTFacility(address(old), address(replacement));

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = held;
        tokenIds[1] = notHeld;

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTFacilityBase.NotHeld.selector, address(nft), notHeld));
        old.migrateTokens(address(nft), tokenIds);
    }

    function testNFTMigrateTokensAfterRegistryRepoint() public {
        AgenticNFTVaultFacility old = _createNFTVault(projectOwner);
        AgenticNFTVaultFacility first = _createNFTVault(projectOwner);
        AgenticNFTVaultFacility second = _createNFTVault(projectOwner);
        uint256 tokenId = _mintNFT(nft, address(old));
        _revokeNFTFacility(address(old));
        _setNFTReplacement(address(old), address(first));
        _migrateNFTFacility(address(old), address(first));

        _setNFTReplacement(address(old), address(second));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTFacilityBase.MigrationTargetNotActive.selector, address(first))
        );
        old.migrateTokens(address(nft), tokenIds);

        _migrateNFTFacility(address(old), address(second));

        vm.prank(projectOwner);
        old.migrateTokens(address(nft), tokenIds);
        assertEq(nft.ownerOf(tokenId), address(second));
    }

    function testNFTGameMigrateTokensToReplacement() public {
        AgenticNFTGameFacility old = _createNFTGame(projectOwner, projectOwner);
        AgenticNFTGameFacility replacement = _createNFTGame(projectOwner, projectOwner);
        uint256 tokenId = _mintNFT(nft, agent);
        _depositNFT(nft, address(old), tokenId);

        _revokeNFTFacility(address(old));
        _setNFTReplacement(address(old), address(replacement));
        _migrateNFTFacility(address(old), address(replacement));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        vm.prank(projectOwner);
        old.migrateTokens(address(nft), tokenIds);

        assertEq(nft.ownerOf(tokenId), address(replacement));
        assertEq(old.migrationTarget(), address(replacement));
    }

    function testNFTMigrateTokensToTargetUsesActiveTargetException() public {
        // The migration target is a facility, so it only passes the gated
        // recipient guard through the active-target exception.
        AgenticNFTVaultFacility old = _createNFTVault(projectOwner);
        AgenticNFTVaultFacility replacement = _createNFTVault(projectOwner);
        uint256 tokenId = _mintNFT(nft, address(old));
        _revokeNFTFacility(address(old));
        _setNFTReplacement(address(old), address(replacement));
        _migrateNFTFacility(address(old), address(replacement));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        vm.prank(projectOwner);
        old.migrateTokens(address(nft), tokenIds);
        assertEq(nft.ownerOf(tokenId), address(replacement));
    }

    // ------------------------------------------------------- deposit guards

    function testNFTAgentCannotDepositToCustodyFacility() public {
        uint256 tokenId = _mintNFT(nft, agent);

        vm.prank(agent);
        vm.expectRevert();
        nft.safeTransferFrom(agent, address(nftVault), tokenId);
    }

    function testNFTLockerMigrationBeforeUnlockRejected() public {
        AgenticNFTLockerFacility old = _createNFTLocker(projectOwner, agent, DEFAULT_UNLOCK_TIME);
        AgenticNFTLockerFacility replacement = _createNFTLocker(projectOwner, agent, DEFAULT_UNLOCK_TIME);
        uint256 tokenId = _mintNFT(nft, address(old));
        _revokeNFTFacility(address(old));
        _setNFTReplacement(address(old), address(replacement));
        _migrateNFTFacility(address(old), address(replacement));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticNFTLockerFacility.UnlockTimeNotReached.selector, DEFAULT_UNLOCK_TIME)
        );
        old.migrateTokens(address(nft), tokenIds);

        vm.warp(DEFAULT_UNLOCK_TIME);
        vm.prank(projectOwner);
        old.migrateTokens(address(nft), tokenIds);
        assertEq(nft.ownerOf(tokenId), address(replacement));
    }

    function testNFTEscrowRedepositAfterSettlement() public {
        uint256 tokenId = _mintNFT(nft, agent);
        _depositNFT(nft, address(escrow), tokenId);

        vm.prank(agent);
        escrow.release(address(nft), tokenId, agent2);

        vm.prank(agent2);
        nft.safeTransferFrom(agent2, address(escrow), tokenId);

        vm.prank(projectOwner);
        escrow.refund(address(nft), tokenId, agent2);
        assertEq(nft.ownerOf(tokenId), agent2);
    }

    function testNFTMigrateTokensRejectsConsumedGameToken() public {
        AgenticNFTGameFacility old = _createNFTGame(projectOwner, projectOwner);
        AgenticNFTGameFacility replacement = _createNFTGame(projectOwner, projectOwner);
        uint256 tokenId = _mintNFT(nft, address(old));

        vm.prank(projectOwner);
        old.consume(address(nft), tokenId);

        _revokeNFTFacility(address(old));
        _setNFTReplacement(address(old), address(replacement));
        _migrateNFTFacility(address(old), address(replacement));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticNFTGameFacility.TokenConsumed.selector, address(nft), tokenId));
        old.migrateTokens(address(nft), tokenIds);
    }
}
