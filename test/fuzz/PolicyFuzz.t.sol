// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TransferKind} from "../../contracts/common/Types.sol";
import {PolicyVenueFixture} from "../helpers/PolicyVenueFixture.sol";

contract PolicyFuzzTest is PolicyVenueFixture {
    function setUp() public {
        _deployPolicyVenue();
    }

    function _expectedMatrix(uint8 fromIdx, uint8 toIdx) internal pure returns (bool) {
        if (fromIdx == 0) return toIdx == 0 || toIdx == 1 || toIdx == 5;
        if (fromIdx == 1) return toIdx == 0 || toIdx == 3;
        return toIdx == 0;
    }

    function _transferWithContext(address from, address to, bytes memory context)
        internal
        view
        returns (bool allowed, bytes32 reason)
    {
        return policy.canTransfer(address(0x1234), from, to, address(0x9999), context);
    }

    function _isValidContext(bytes memory context) internal pure returns (bool) {
        if (context.length != 32) return false;
        uint256 word;
        assembly ("memory-safe") {
            word := mload(add(context, 0x20))
        }
        return word == uint256(TransferKind.TRANSFER);
    }

    function testFuzzCategoryMatrix(uint8 fromIdx, uint8 toIdx) public view {
        uint8 i = uint8(bound(fromIdx, 0, 5));
        uint8 j = uint8(bound(toIdx, 0, 5));
        address[6] memory froms =
            [agent, address(pool), address(lpManager), address(feeRecipient), address(vault), address(game)];
        address[6] memory tos =
            [agent2, address(pool), address(lpManager), address(feeRecipient), address(vault), address(game)];

        (bool allowed,) = _transfer(froms[i], tos[j]);
        assertEq(allowed, _expectedMatrix(i, j));
    }

    function testFuzzUnknownAddressesDeniedBothDirections(address from, address to) public view {
        vm.assume(from != address(0) && to != address(0));
        vm.assume(!_isKnownPolicyVenueAddress(from) && !_isKnownPolicyVenueAddress(to));

        (bool allowed,) = _transfer(from, to);
        assertFalse(allowed);
        (allowed,) = _transfer(to, from);
        assertFalse(allowed);
    }

    function testFuzzUnknownRecipientNeverEligible(address to) public view {
        vm.assume(to != address(0));
        vm.assume(!_isKnownPolicyVenueAddress(to));
        (bool allowed,) = _transfer(address(0), to);
        assertFalse(allowed);
    }

    function testFuzzContextMustBeExactlyTransfer(bytes memory context) public view {
        bool valid = _isValidContext(context);
        (bool allowed,) = _transferWithContext(agent, agent2, context);
        assertEq(allowed, valid);
    }

    function testFuzzFacilityNeverSendsToUnknown(address to) public view {
        vm.assume(!_isKnownPolicyVenueAddress(to));
        vm.assume(to != address(0));

        (bool allowed,) = _transfer(address(pool), to);
        assertFalse(allowed);
        (allowed,) = _transfer(address(vault), to);
        assertFalse(allowed);
        (allowed,) = _transfer(address(game), to);
        assertFalse(allowed);
        (allowed,) = _transfer(address(lpManager), to);
        assertFalse(allowed);
        (allowed,) = _transfer(address(feeRecipient), to);
        assertFalse(allowed);
    }
}
