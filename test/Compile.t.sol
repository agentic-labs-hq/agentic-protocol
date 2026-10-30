// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

// Compile-verify the pinned OpenZeppelin modules used by the protocol implementation.
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    AssetType,
    FacilityCategory,
    TransferKind,
    POOL,
    NPM,
    TREASURY,
    VAULT,
    LAUNCH,
    LOCKER,
    GAME,
    ESCROW,
    LENDING,
    MARKET
} from "../contracts/common/Types.sol";
import {NonRevocableFacility} from "../contracts/common/Errors.sol";
import {IGovernance} from "../contracts/interfaces/IGovernance.sol";
import {IPolicyRegistry} from "../contracts/interfaces/IPolicyRegistry.sol";
import {IAgentAsset, IAgentToken} from "../contracts/interfaces/IAgentAsset.sol";
import {ITransferPolicy} from "../contracts/interfaces/ITransferPolicy.sol";
import {IIdentityAdapter, IIdentityAdapterRegistry} from "../contracts/interfaces/IIdentityAdapter.sol";
import {IFacility, IMigratableFacility} from "../contracts/interfaces/IFacility.sol";
import {IVenueRegistry} from "../contracts/interfaces/IVenueRegistry.sol";
import {IAssetRegistry} from "../contracts/interfaces/IAssetRegistry.sol";
import {IQuoteAssetRegistry} from "../contracts/interfaces/IQuoteAssetRegistry.sol";
import {IProtocolTreasury} from "../contracts/interfaces/IProtocolTreasury.sol";
import {
    ICustodyFacility,
    IVaultFacility,
    ILaunchFacility,
    ILockerFacility
} from "../contracts/interfaces/ICustodyFacility.sol";
import {
    IPurposeFacility,
    IGameFacility,
    IEscrowFacility,
    ILendingFacility
} from "../contracts/interfaces/IPurposeFacility.sol";
import {IFacilityFactory} from "../contracts/interfaces/IFacilityFactory.sol";
import {IGatedPoolFactory} from "../contracts/interfaces/IGatedPoolFactory.sol";
import {IAgentTokenFactory} from "../contracts/interfaces/IAgentTokenFactory.sol";
import {IGatedPositionManager} from "../contracts/interfaces/IGatedPositionManager.sol";

/// @notice protocol compile smoke test: every frozen v2.2 interface and shared type
/// is imported and the baseline toolchain compiles it. No protocol logic.
contract CompileTest is Test {
    function testFoundationCompiles() public pure {
        assertEq(uint256(AssetType.FT), 0);
        assertEq(uint256(AssetType.NFT), 1);
        assertEq(uint256(FacilityCategory.PURPOSE), 5);
        assertEq(uint256(TransferKind.TRANSFER), 0);
        assertEq(POOL, keccak256("POOL"));
        assertEq(NonRevocableFacility.selector, bytes4(keccak256("NonRevocableFacility()")));
    }
}
