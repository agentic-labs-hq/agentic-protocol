// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {AgenticIdAdapter} from "../../contracts/identity/AgenticIdAdapter.sol";
import {AGENT_ID_KIND, IAgentIdRegistry} from "../../contracts/identity/IAgentIdRegistry.sol";

/// @notice Read-only fork verification against the live BSC Agent ID registry.
/// @dev Run with an archive-capable RPC and an explicitly supplied test identity:
/// `BSC_RPC_URL=<rpc> BSC_TEST_AGENT=<address> BSC_TEST_HANDLE=<handle> \
///  forge test --match-path test/fork/AgenticIdAdapter.fork.t.sol -vv`
/// The default pinned block is 129000000. Set `BSC_FORK_BLOCK=<block>` to
/// override it, or `BSC_FORK_BLOCK=0` to use the RPC's latest block. Without
/// all three values every test in this suite is skipped. There is no committed
/// default identity.
contract AgenticIdAdapterForkTest is Test {
    address internal constant REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    address internal constant NON_AGENT = address(0x1111111111111111111111111111111111111111);
    uint256 internal constant PINNED_BLOCK = 129_000_000;

    AgenticIdAdapter internal adapter;
    address internal agent;
    string internal handle;
    bool internal forkReady;

    function setUp() public {
        string memory rpcUrl = vm.envOr("BSC_RPC_URL", string(""));
        agent = vm.envOr("BSC_TEST_AGENT", address(0));
        handle = vm.envOr("BSC_TEST_HANDLE", string(""));
        if (bytes(rpcUrl).length == 0 || agent == address(0) || bytes(handle).length == 0) return;

        uint256 forkBlock = vm.envOr("BSC_FORK_BLOCK", PINNED_BLOCK);
        if (forkBlock == 0) {
            vm.createSelectFork(rpcUrl);
        } else {
            vm.createSelectFork(rpcUrl, forkBlock);
        }

        adapter = new AgenticIdAdapter(IAgentIdRegistry(REGISTRY));
        forkReady = true;
    }

    modifier onlyFork() {
        if (!forkReady) {
            vm.skip(true);
            return;
        }
        _;
    }

    function testForkAbiAndEligibility() public onlyFork {
        assertEq(block.chainid, 56);
        assertEq(adapter.chainId(), 56);
        assertEq(adapter.kind(), AGENT_ID_KIND);
        assertEq(adapter.version(), 1);

        // The three adapter ABI calls decode correctly against the real registry.
        IAgentIdRegistry registry = IAgentIdRegistry(REGISTRY);
        assertEq(registry.balanceOf(agent), 1);
        assertEq(registry.handleOf(agent), handle);
        assertEq(registry.ownerOfHandle(handle), agent);

        assertTrue(adapter.hasIdentity(agent));

        bytes32 expectedHash = keccak256(bytes(handle));
        (uint256 tokenId, bytes32 handleHash) = adapter.identityOf(agent);
        assertEq(tokenId, uint256(expectedHash));
        assertEq(handleHash, expectedHash);

        (uint256 requiredId, bytes32 requiredHash) = adapter.requireIdentity(agent);
        assertEq(requiredId, tokenId);
        assertEq(requiredHash, handleHash);
    }

    function testForkNonAgent() public onlyFork {
        IAgentIdRegistry registry = IAgentIdRegistry(REGISTRY);
        assertEq(registry.balanceOf(NON_AGENT), 0);
        assertEq(registry.handleOf(NON_AGENT), "");

        assertFalse(adapter.hasIdentity(NON_AGENT));
        (uint256 tokenId, bytes32 handleHash) = adapter.identityOf(NON_AGENT);
        assertEq(tokenId, 0);
        assertEq(handleHash, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(AgenticIdAdapter.NotAgent.selector, NON_AGENT));
        adapter.requireIdentity(NON_AGENT);
    }

    function testForkZeroWalletShortCircuits() public onlyFork {
        // The live registry reverts on balanceOf(address(0)); the adapter must
        // return false without making that call.
        assertFalse(adapter.hasIdentity(address(0)));

        vm.expectRevert();
        IAgentIdRegistry(REGISTRY).balanceOf(address(0));
    }

    function testForkUnknownHandleHasNoOwner() public onlyFork {
        assertEq(IAgentIdRegistry(REGISTRY).ownerOfHandle("no-such-agent-id-handle"), address(0));
    }
}
