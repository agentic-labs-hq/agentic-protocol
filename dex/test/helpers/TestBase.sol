// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

/// @dev Minimal subset of the Foundry cheatcode interface (no forge-std).
interface Vm {
    function assume(bool condition) external;

    function prank(address sender) external;
    function startPrank(address sender) external;
    function stopPrank() external;

    function expectRevert() external;
    function expectRevert(bytes calldata revertData) external;
    function expectRevert(bytes4 revertData) external;

    function getCode(string calldata artifactPath) external returns (bytes memory);
    function getDeployedCode(string calldata artifactPath) external view returns (bytes memory);
    function deployCode(string calldata artifactPath, bytes calldata constructorArgs) external returns (address);
    function etch(address target, bytes calldata newRuntimeBytecode) external;
}

/// @dev Minimal assertion helpers for the dex test project (0.7.6).
abstract contract TestBase {
    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function assertTrue(bool condition) internal pure {
        require(condition, "assertTrue failed");
    }

    function assertFalse(bool condition) internal pure {
        require(!condition, "assertFalse failed");
    }

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "assertEq(uint256) failed");
    }

    function assertEq(address actual, address expected) internal pure {
        require(actual == expected, "assertEq(address) failed");
    }

    function assertEq(bytes4 actual, bytes4 expected) internal pure {
        require(actual == expected, "assertEq(bytes4) failed");
    }

    function expectRevertSelector(bytes4 selector) internal {
        vm.expectRevert(selector);
    }
}
