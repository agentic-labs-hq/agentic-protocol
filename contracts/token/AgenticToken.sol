// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAgentAsset, IAgentToken} from "../interfaces/IAgentAsset.sol";
import {ITransferPolicy} from "../interfaces/ITransferPolicy.sol";
import {AssetType, TransferKind} from "../common/Types.sol";

/// @notice Gated fixed-supply FT for a single policy version.
/// @dev Deployed only by `AgenticTokenFactory`; the constructor mints the whole
/// initial supply directly to the approved recipients, so the factory never
/// holds tokens. The supply is fixed after construction: there is no mint,
/// burn, pause, admin or proxy path. Every `_update` (mint, transfer and
/// transferFrom) asks the immutable `ITransferPolicy` and reverts on denial.
///
/// `metadataURI` is write-once storage rather than an `immutable`: solc 0.8.20
/// only permits immutable value types, not strings. It is assigned only in the
/// constructor, has no setter, and is therefore immutable in behavior.
contract AgenticToken is ERC20, IAgentToken {
    /// @notice Thrown when anyone other than the declared factory constructs the token.
    error NotFactory(address caller);
    /// @notice Thrown when the transfer policy denies a mint/transfer.
    error TransferDenied(bytes32 reason);
    /// @notice Thrown for a zero policy or creator address.
    error InvalidConfiguration();
    /// @notice Thrown when the recipient and amount arrays differ in length.
    error LengthMismatch();
    /// @notice Thrown when no initial recipient is supplied.
    error NoInitialRecipients();
    /// @notice Thrown when the total initial supply is zero.
    error NoInitialSupply();
    /// @notice Thrown when a recipient is the zero address.
    error ZeroRecipient();

    /// @inheritdoc IAgentToken
    address public immutable override factory;

    /// @inheritdoc IAgentAsset
    address public immutable override policy;

    /// @inheritdoc IAgentAsset
    address public immutable override creator;

    string private _metadataURI;

    /// @param name_ ERC-20 name.
    /// @param symbol_ ERC-20 symbol.
    /// @param factory_ The only address allowed to deploy; must be `msg.sender`.
    /// @param policy_ Immutable transfer policy version selected for this token.
    /// @param creator_ The factory caller (agent or project) recorded as creator.
    /// @param initialRecipients Eligible agents and/or active CUSTODY/PURPOSE facilities.
    /// @param initialAmounts Initial amounts minted to `initialRecipients`.
    /// @param metadataURI_ Off-chain metadata URI; write-once.
    constructor(
        string memory name_,
        string memory symbol_,
        address factory_,
        address policy_,
        address creator_,
        address[] memory initialRecipients,
        uint256[] memory initialAmounts,
        string memory metadataURI_
    ) ERC20(name_, symbol_) {
        if (msg.sender != factory_) revert NotFactory(msg.sender);
        if (policy_ == address(0) || creator_ == address(0)) revert InvalidConfiguration();
        if (initialRecipients.length != initialAmounts.length) revert LengthMismatch();
        if (initialRecipients.length == 0) revert NoInitialRecipients();

        factory = factory_;
        policy = policy_;
        creator = creator_;
        _metadataURI = metadataURI_;

        uint256 total = 0;
        uint256 count = initialRecipients.length;
        for (uint256 i; i < count; ++i) {
            address recipient = initialRecipients[i];
            if (recipient == address(0)) revert ZeroRecipient();
            uint256 amount = initialAmounts[i];
            total += amount;
            _mint(recipient, amount);
        }
        if (total == 0) revert NoInitialSupply();
    }

    /// @inheritdoc IAgentAsset
    /// @dev 18 decimals is the OZ ERC20 default; no override is needed.
    function assetType() external pure override returns (AssetType) {
        return AssetType.FT;
    }

    /// @inheritdoc IAgentAsset
    function metadataURI() external view override returns (string memory) {
        return _metadataURI;
    }

    /// @dev Gate every balance movement, including the constructor mint, through
    /// the immutable policy. The operator is the token caller (`_msgSender()`)
    /// and the context is exactly `abi.encode(TransferKind.TRANSFER)`.
    function _update(address from, address to, uint256 value) internal override {
        (bool allowed, bytes32 reason) = ITransferPolicy(policy)
            .canTransfer(address(this), from, to, _msgSender(), abi.encode(TransferKind.TRANSFER));
        if (!allowed) revert TransferDenied(reason);
        super._update(from, to, value);
    }
}
