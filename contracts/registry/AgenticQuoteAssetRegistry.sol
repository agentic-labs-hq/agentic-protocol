// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Governance2Step} from "../common/Governance2Step.sol";
import {IAssetRegistry} from "../interfaces/IAssetRegistry.sol";
import {IQuoteAssetRegistry} from "../interfaces/IQuoteAssetRegistry.sol";

/// @dev Minimal ERC-20 getters used to reject non-token contracts.
interface IERC20Probe {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Governance-managed quote-asset allowlist.
/// @dev Quote assets are public ERC-20s only: gated assets (registered in
/// `AgenticAssetRegistry`) and arbitrary codeless/non-ERC-20 addresses are rejected.
/// The list is capped and managed by two-step governance. An optional initial
/// list is supplied at deployment (WBNB/USDT); entries go through the same
/// checks as a governance `addQuoteAsset` call.
contract AgenticQuoteAssetRegistry is IQuoteAssetRegistry, Governance2Step {
    /// @inheritdoc IQuoteAssetRegistry
    address public immutable override assetRegistry;

    /// @inheritdoc IQuoteAssetRegistry
    uint256 public immutable override maxQuoteAssets;

    /// @inheritdoc IQuoteAssetRegistry
    mapping(address => bool) public override isQuoteAsset;

    address[] private _quoteAssets;
    mapping(address => uint256) private _index;

    /// @notice Thrown when the asset registry is zero or codeless.
    error InvalidAssetRegistry(address assetRegistry);
    /// @notice Thrown when the quote-asset cap is zero.
    error InvalidMaxQuoteAssets();
    /// @notice Thrown for the zero token address.
    error ZeroToken();
    /// @notice Thrown when the token has no code.
    error TokenHasNoCode(address token);
    /// @notice Thrown when the token is already a quote asset.
    error QuoteAssetAlreadyAdded(address token);
    /// @notice Thrown when the token is a registered gated asset.
    error GatedAssetNotAllowed(address token);
    /// @notice Thrown when the token fails the ERC-20 probe.
    error NotERC20(address token);
    /// @notice Thrown when the quote-asset cap is reached.
    error QuoteCapReached(uint256 maxQuoteAssets);
    /// @notice Thrown when the token is not a quote asset.
    error QuoteAssetNotListed(address token);

    /// @param governance_ Initial two-step governance.
    /// @param assetRegistry_ Asset registry used to reject gated assets.
    /// @param maxQuoteAssets_ Maximum number of quote assets.
    /// @param initialQuoteAssets Optional deployment list (e.g. WBNB/USDT).
    constructor(
        address governance_,
        address assetRegistry_,
        uint256 maxQuoteAssets_,
        address[] memory initialQuoteAssets
    ) Governance2Step(governance_) {
        if (assetRegistry_ == address(0) || assetRegistry_.code.length == 0) {
            revert InvalidAssetRegistry(assetRegistry_);
        }
        if (maxQuoteAssets_ == 0) revert InvalidMaxQuoteAssets();

        assetRegistry = assetRegistry_;
        maxQuoteAssets = maxQuoteAssets_;

        uint256 count = initialQuoteAssets.length;
        for (uint256 i; i < count; ++i) {
            _addQuoteAsset(initialQuoteAssets[i]);
        }
    }

    /// @inheritdoc IQuoteAssetRegistry
    function quoteAssets() external view override returns (address[] memory) {
        return _quoteAssets;
    }

    /// @inheritdoc IQuoteAssetRegistry
    /// @dev Governance-only. Rejects gated assets, duplicates, codeless
    /// addresses, non-ERC-20 contracts and a full list.
    function addQuoteAsset(address token) external override onlyGovernance {
        _addQuoteAsset(token);
    }

    /// @inheritdoc IQuoteAssetRegistry
    /// @dev Governance-only. Removal swaps the last entry into the removed slot;
    /// order is not part of the interface contract.
    function removeQuoteAsset(address token) external override onlyGovernance {
        if (!isQuoteAsset[token]) revert QuoteAssetNotListed(token);

        isQuoteAsset[token] = false;
        uint256 index = _index[token];
        uint256 last = _quoteAssets.length;
        if (index != last) {
            address moved = _quoteAssets[last - 1];
            _quoteAssets[index - 1] = moved;
            _index[moved] = index;
        }
        _quoteAssets.pop();
        delete _index[token];

        emit QuoteAssetRemoved(token);
    }

    /// @dev Shared add path for the constructor and governance.
    function _addQuoteAsset(address token) private {
        if (token == address(0)) revert ZeroToken();
        if (token.code.length == 0) revert TokenHasNoCode(token);
        if (isQuoteAsset[token]) revert QuoteAssetAlreadyAdded(token);
        if (IAssetRegistry(assetRegistry).isRegistered(token)) revert GatedAssetNotAllowed(token);
        if (_quoteAssets.length >= maxQuoteAssets) revert QuoteCapReached(maxQuoteAssets);
        _requireERC20(token);

        isQuoteAsset[token] = true;
        _quoteAssets.push(token);
        _index[token] = _quoteAssets.length;
        emit QuoteAssetAdded(token);
    }

    /// @dev Probes `totalSupply()` and `balanceOf(address(this))`; a failed call
    /// or a short/non-decodable return is not an ERC-20.
    function _requireERC20(address token) private view {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeCall(IERC20Probe.totalSupply, ()));
        if (!ok || data.length < 32) revert NotERC20(token);
        (ok, data) = token.staticcall(abi.encodeCall(IERC20Probe.balanceOf, (address(this))));
        if (!ok || data.length < 32) revert NotERC20(token);
    }
}
