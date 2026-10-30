// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFacility, IMigratableFacility} from "./IFacility.sol";

/// @notice Purpose facility interface.
interface IPurposeFacility is IFacility, IMigratableFacility {
    function consume(address token, uint256 amount) external; // GAME only; lock/consume
    function release(address token, address to, uint256 amount) external;
    function refund(address token, address to, uint256 amount) external;
    function liquidate(address token, address to, uint256 amount) external; // LENDING only
}

/// @notice GAME template interface (PURPOSE subtype).
interface IGameFacility is IPurposeFacility {
    function operator() external view returns (address);
    function setOperator(address operator) external;
    event OperatorSet(address indexed operator);
}

/// @notice ESCROW template interface (PURPOSE subtype).
interface IEscrowFacility is IPurposeFacility {
    function arbiter() external view returns (address);
    function beneficiary() external view returns (address);
    function setArbiter(address arbiter) external;
    function setBeneficiary(address beneficiary) external;
    function deposit(address token, uint256 amount) external;

    event ArbiterSet(address indexed arbiter);
    event BeneficiarySet(address indexed beneficiary);
}

/// @notice LENDING template interface (PURPOSE subtype).
interface ILendingFacility is IPurposeFacility {
    function keeper() external view returns (address);
    function oracle() external view returns (address);
    function setKeeper(address keeper) external;
    function setOracle(address oracle) external;
    function deposit(address token, uint256 amount) external;
    function borrow(address token, uint256 amount) external;
    function repay(address token, uint256 amount) external;
    function withdraw(address token, address to, uint256 amount) external;

    event KeeperSet(address indexed keeper);
    event OracleSet(address indexed oracle);
}
