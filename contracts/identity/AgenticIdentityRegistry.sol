// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGovernance} from "../interfaces/IGovernance.sol";
import {IIdentityAdapter, IIdentityAdapterRegistry} from "../interfaces/IIdentityAdapter.sol";

/// @title AgenticIdentityRegistry
/// @notice Governance-controlled registry of identity adapters, one per kind.
/// @dev The registry never calls arbitrary contracts beyond the adapter's
/// `kind()` view. Adapters are registered/replaced/disabled by two-step
/// governance only; there is no admin backdoor and no proxy.
contract AgenticIdentityRegistry is IIdentityAdapterRegistry {
    error NotGovernance();
    error NotPendingGovernance();
    error InvalidGovernance();
    error InvalidMaxAdapters();
    error InvalidAdapter();
    error AdapterNotContract();
    error InvalidKind();
    error KindMismatch(bytes32 expectedKind, bytes32 adapterKind);
    error KindAlreadyRegistered(bytes32 kind);
    error AdapterAlreadyRegistered(address adapter);
    error MaxAdaptersReached(uint256 maxAdapters);
    error NoAdapterForKind(bytes32 kind);
    error AdapterAlreadyEnabled(address adapter);
    error AdapterNotEnabled(address adapter);
    error LastAdapter();

    /// @inheritdoc IIdentityAdapterRegistry
    uint256 public immutable override maxAdapters;

    /// @inheritdoc IGovernance
    address public override governance;

    /// @inheritdoc IGovernance
    address public override pendingGovernance;

    /// @inheritdoc IIdentityAdapterRegistry
    mapping(bytes32 kind => address adapter) public override adapterOf;

    /// @inheritdoc IIdentityAdapterRegistry
    mapping(address adapter => bool enabled) public override isEnabled;

    address[] private _enabledAdapters;

    /// @dev Kind of each currently enabled adapter; zero when not enabled.
    mapping(address adapter => bytes32 kind) private _kindOf;

    /// @dev 1-based index of each currently enabled adapter in `_enabledAdapters`.
    mapping(address adapter => uint256 index) private _indexOf;

    /// @param maxAdapters_ Maximum number of simultaneously enabled adapters.
    /// @dev The deployer becomes `governance` and can transfer it in two steps.
    constructor(uint256 maxAdapters_) {
        if (maxAdapters_ == 0) revert InvalidMaxAdapters();
        maxAdapters = maxAdapters_;
        governance = msg.sender;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        _;
    }

    /// @inheritdoc IIdentityAdapterRegistry
    /// @dev Registers a code-backed adapter under a new kind. The adapter's
    /// self-reported `kind()` must match the supplied kind exactly. One adapter
    /// per kind and at most `maxAdapters` enabled adapters.
    function registerAdapter(address adapter, bytes32 kind) external override onlyGovernance {
        if (adapter == address(0)) revert InvalidAdapter();
        if (adapter.code.length == 0) revert AdapterNotContract();
        if (kind == bytes32(0)) revert InvalidKind();
        if (adapterOf[kind] != address(0)) revert KindAlreadyRegistered(kind);
        if (_kindOf[adapter] != bytes32(0)) revert AdapterAlreadyRegistered(adapter);
        if (_enabledAdapters.length >= maxAdapters) revert MaxAdaptersReached(maxAdapters);

        bytes32 adapterKind = IIdentityAdapter(adapter).kind();
        if (adapterKind != kind) revert KindMismatch(kind, adapterKind);

        adapterOf[kind] = adapter;
        isEnabled[adapter] = true;
        _kindOf[adapter] = kind;
        _enabledAdapters.push(adapter);
        _indexOf[adapter] = _enabledAdapters.length;

        emit AdapterRegistered(adapter, kind);
    }

    /// @inheritdoc IIdentityAdapterRegistry
    /// @dev Atomically swaps the adapter registered under `newAdapter.kind()`
    /// for `newAdapter`. The old adapter is disabled in the same transaction.
    function replaceAdapter(address newAdapter) external override onlyGovernance {
        if (newAdapter == address(0)) revert InvalidAdapter();
        if (newAdapter.code.length == 0) revert AdapterNotContract();

        bytes32 kind = IIdentityAdapter(newAdapter).kind();
        if (kind == bytes32(0)) revert InvalidKind();

        address oldAdapter = adapterOf[kind];
        if (oldAdapter == address(0)) revert NoAdapterForKind(kind);
        if (newAdapter == oldAdapter || isEnabled[newAdapter] || _kindOf[newAdapter] != bytes32(0)) {
            revert AdapterAlreadyEnabled(newAdapter);
        }

        uint256 index = _indexOf[oldAdapter];
        _enabledAdapters[index - 1] = newAdapter;
        _indexOf[newAdapter] = index;
        delete _indexOf[oldAdapter];

        isEnabled[oldAdapter] = false;
        delete _kindOf[oldAdapter];
        isEnabled[newAdapter] = true;
        _kindOf[newAdapter] = kind;
        adapterOf[kind] = newAdapter;

        emit AdapterReplaced(oldAdapter, newAdapter, kind);
    }

    /// @inheritdoc IIdentityAdapterRegistry
    /// @dev Removes an enabled adapter. The last enabled adapter cannot be
    /// disabled; governance must replace it instead.
    function disableAdapter(address adapter) external override onlyGovernance {
        bytes32 kind = _kindOf[adapter];
        if (kind == bytes32(0) || !isEnabled[adapter]) revert AdapterNotEnabled(adapter);
        if (_enabledAdapters.length == 1) revert LastAdapter();

        uint256 index = _indexOf[adapter] - 1;
        uint256 lastIndex = _enabledAdapters.length - 1;
        if (index != lastIndex) {
            address lastAdapter = _enabledAdapters[lastIndex];
            _enabledAdapters[index] = lastAdapter;
            _indexOf[lastAdapter] = index + 1;
        }
        _enabledAdapters.pop();
        delete _indexOf[adapter];

        isEnabled[adapter] = false;
        delete _kindOf[adapter];
        adapterOf[kind] = address(0);

        emit AdapterDisabled(adapter, kind);
    }

    /// @inheritdoc IIdentityAdapterRegistry
    function enabledAdapters() external view override returns (address[] memory) {
        return _enabledAdapters;
    }

    /// @inheritdoc IGovernance
    /// @dev First step of the two-step governance transfer. The current
    /// governance remains in control until the pending governance accepts.
    function transferGovernance(address newGovernance) external override onlyGovernance {
        if (newGovernance == address(0) || newGovernance == governance) revert InvalidGovernance();
        // The frozen IGovernance event is emitted below; forge-lint does not
        // resolve events inherited from an interface.
        // forge-lint: disable-next-line(missing-events-access-control)
        pendingGovernance = newGovernance;
        emit GovernanceTransferStarted(governance, newGovernance);
    }

    /// @inheritdoc IGovernance
    /// @dev Second step of the two-step governance transfer.
    function acceptGovernance() external override {
        if (msg.sender != pendingGovernance) revert NotPendingGovernance();
        address previous = governance;
        governance = msg.sender;
        // The frozen IGovernance event is emitted below; forge-lint does not
        // resolve events inherited from an interface.
        // forge-lint: disable-next-line(missing-events-access-control)
        pendingGovernance = address(0);
        emit GovernanceTransferred(previous, msg.sender);
    }
}
