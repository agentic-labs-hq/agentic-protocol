// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Shared custom errors referenced by the frozen v2.2 behavior.
/// @dev the initial protocol release defines only errors explicitly named by the public interfaces; each
/// implementation workstream may add its own local errors without changing
/// any public interface signature.
error NonRevocableFacility();
