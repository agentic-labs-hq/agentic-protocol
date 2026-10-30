// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgenticFacilityBase} from "../../contracts/facility/AgenticFacilityBase.sol";
import {AgenticFacilityFactory} from "../../contracts/facility/AgenticFacilityFactory.sol";
import {AgenticLockerFacility} from "../../contracts/facility/AgenticLockerFacility.sol";
import {AgenticVaultFacility} from "../../contracts/facility/AgenticVaultFacility.sol";
import {AgenticToken} from "../../contracts/token/AgenticToken.sol";

import {MockToken} from "../mocks/MockToken.sol";
import {FacilityFixture} from "../helpers/FacilityFixture.sol";

contract AgenticLockerFacilityTest is FacilityFixture {
    AgenticLockerFacility internal locker;
    AgenticToken internal token;

    function setUp() public {
        _deployFacilities();
        locker = _defaultLocker();
        token = _fundLocker(locker, 1_000 ether);
    }

    function testLockerUnlockBeforeTimeReverts() public {
        vm.prank(nonAgent);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticLockerFacility.UnlockTimeNotReached.selector, DEFAULT_UNLOCK_TIME)
        );
        locker.unlock(address(token), agent, 1 ether);
    }

    function testLockerUnlockAfterTimeAnyoneToBeneficiary() public {
        vm.warp(DEFAULT_UNLOCK_TIME);
        vm.prank(nonAgent);
        locker.unlock(address(token), agent, 400 ether);

        assertEq(token.balanceOf(agent), 400 ether);
        assertEq(token.balanceOf(address(locker)), 600 ether);
    }

    function testLockerUnlockRejectsOtherAgent() public {
        vm.warp(DEFAULT_UNLOCK_TIME);
        vm.prank(nonAgent);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticLockerFacility.UnlockRecipientNotBeneficiary.selector, agent2, agent)
        );
        locker.unlock(address(token), agent2, 1 ether);
    }

    function testLockerUnlockRejectsNonAgent() public {
        vm.warp(DEFAULT_UNLOCK_TIME);
        vm.prank(nonAgent);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticLockerFacility.UnlockRecipientNotBeneficiary.selector, nonAgent, agent)
        );
        locker.unlock(address(token), nonAgent, 1 ether);
    }

    function testLockerUnlockRejectsZeroToken() public {
        vm.warp(DEFAULT_UNLOCK_TIME);
        vm.prank(nonAgent);
        vm.expectRevert(AgenticFacilityBase.ZeroToken.selector);
        locker.unlock(address(0), agent, 1 ether);
    }

    function testLockerUnlockRejectsPublicToken() public {
        MockToken publicToken = _publicTokenTo(address(locker), 10 ether);
        vm.warp(DEFAULT_UNLOCK_TIME);

        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotGatedToken.selector, address(publicToken)));
        locker.unlock(address(publicToken), agent, 1 ether);
    }

    function testLockerReleaseAndReleaseNativeAlwaysRevert() public {
        vm.prank(projectOwner);
        vm.expectRevert(AgenticLockerFacility.ReleaseNotSupported.selector);
        locker.release(address(token), agent, 1 ether);

        vm.prank(projectOwner);
        vm.expectRevert(AgenticLockerFacility.NativeNotSupported.selector);
        locker.releaseNative(payable(agent), 1 ether);
    }

    function testLockerExtendAfterUnlockReverts() public {
        vm.warp(DEFAULT_UNLOCK_TIME);
        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticLockerFacility.UnlockTimeReached.selector, DEFAULT_UNLOCK_TIME));
        locker.extend(DEFAULT_UNLOCK_TIME + 1);
    }

    function testLockerExtendOnlyOwnerAndOnlyIncreases() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, agent));
        locker.extend(DEFAULT_UNLOCK_TIME + 1);

        vm.prank(projectOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgenticLockerFacility.UnlockTimeNotExtended.selector, DEFAULT_UNLOCK_TIME, DEFAULT_UNLOCK_TIME
            )
        );
        locker.extend(DEFAULT_UNLOCK_TIME);

        uint64 extended = DEFAULT_UNLOCK_TIME + 1_000;
        vm.prank(projectOwner);
        locker.extend(extended);
        assertEq(locker.unlockTime(), extended);

        vm.warp(DEFAULT_UNLOCK_TIME);
        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSelector(AgenticLockerFacility.UnlockTimeNotReached.selector, extended));
        locker.unlock(address(token), agent, 1 ether);

        vm.warp(extended);
        vm.prank(nonAgent);
        locker.unlock(address(token), agent, 1 ether);
        assertEq(token.balanceOf(agent), 1 ether);
    }

    function testLockerSetBeneficiaryBeforeUnlock() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotOwner.selector, agent));
        locker.setBeneficiary(agent2);

        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.NotAgent.selector, nonAgent));
        locker.setBeneficiary(nonAgent);

        AgenticVaultFacility other = _createVault(projectOwner);
        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityBase.FacilityNotAgent.selector, address(other)));
        locker.setBeneficiary(address(other));

        vm.prank(projectOwner);
        locker.setBeneficiary(agent2);
        assertEq(locker.beneficiary(), agent2);

        vm.warp(DEFAULT_UNLOCK_TIME);
        vm.prank(nonAgent);
        vm.expectRevert(
            abi.encodeWithSelector(AgenticLockerFacility.UnlockRecipientNotBeneficiary.selector, agent, agent2)
        );
        locker.unlock(address(token), agent, 1 ether);

        vm.prank(nonAgent);
        locker.unlock(address(token), agent2, 1 ether);
        assertEq(token.balanceOf(agent2), 1 ether);
    }

    function testLockerSetBeneficiaryAfterUnlockReverts() public {
        vm.warp(DEFAULT_UNLOCK_TIME);
        vm.prank(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticLockerFacility.UnlockTimeReached.selector, DEFAULT_UNLOCK_TIME));
        locker.setBeneficiary(agent2);
    }

    function testLockerSetBeneficiaryRejectsZero() public {
        vm.prank(projectOwner);
        vm.expectRevert(AgenticLockerFacility.ZeroBeneficiary.selector);
        locker.setBeneficiary(address(0));
    }

    function testLockerBeneficiaryCannotBeFacilityAtCreation() public {
        AgenticVaultFacility other = _createVault(projectOwner);
        vm.expectRevert(abi.encodeWithSelector(AgenticFacilityFactory.FacilityNotAgent.selector, address(other)));
        _createLocker(projectOwner, address(other), DEFAULT_UNLOCK_TIME);
    }
}
