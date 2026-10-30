// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint128.sol';
import '@uniswap/v3-core/contracts/libraries/FullMath.sol';

import './interfaces/INonfungiblePositionManager.sol';
import './interfaces/INonfungibleTokenPositionDescriptor.sol';
import './interfaces/IGatedAssetRegistry.sol';
import './interfaces/IGatedTransferPolicy.sol';
import './libraries/PositionKey.sol';
import './libraries/PoolAddress.sol';
import './base/LiquidityManagement.sol';
import './base/PeripheryImmutableState.sol';
import './base/Multicall.sol';
import './base/ERC721Permit.sol';
import './base/PeripheryValidation.sol';
import './base/SelfPermit.sol';
import './base/PoolInitializer.sol';

/// @title NFT positions
/// @notice Wraps Uniswap V3 positions in the ERC721 non-fungible token interface
/// @dev Gated LP only: the token's policy gates mint/transfer/ops/collect.
/// Residual: `IUniswapV3Pool.mint` remains callable directly and creates a raw
/// V3 position without an NPM LP NFT. The token policy still rejects a
/// non-agent recipient, but the raw position bypasses this gate; closing it
/// requires an AMM core change and is a documented M2/M4 residual.
contract AgentswapPositionManager is
    INonfungiblePositionManager,
    Multicall,
    ERC721Permit,
    PeripheryImmutableState,
    PoolInitializer,
    LiquidityManagement,
    PeripheryValidation,
    SelfPermit
{
    // details about the uniswap position
    struct Position {
        // the nonce for permits
        uint96 nonce;
        // the address that is approved for spending this token
        address operator;
        // the ID of the pool with which this token is connected
        uint80 poolId;
        // the tick range of the position
        int24 tickLower;
        int24 tickUpper;
        // the liquidity of the position
        uint128 liquidity;
        // the fee growth of the aggregate position as of the last action on the individual position
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        // how many uncollected tokens are owed to the position, as of the last computation
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    /// @dev IDs of pools assigned by this contract
    mapping(address => uint80) private _poolIds;

    /// @dev Pool keys by pool ID, to save on SSTOREs for position data
    mapping(uint80 => PoolAddress.PoolKey) private _poolIdToPoolKey;

    /// @dev The token ID position data
    mapping(uint256 => Position) private _positions;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint176 private _nextId = 1;
    /// @dev The ID of the next pool that is used for the first time. Skips 0
    uint80 private _nextPoolId = 1;

    /// @dev The address of the token descriptor contract, which handles generating token URIs for position tokens
    address private immutable _tokenDescriptor;

    /// @dev Gated asset registry; per-token policies are resolved from it.
    /// Immutable and code-checked at construction. There is no setter and no
    /// global policy: every gated token in a position uses its own policy.
    address private immutable assetRegistry;

    /// @dev Gate errors. 0.7.6 predates custom errors, so each is a 4-byte
    /// selector reverted directly (the same ABI shape as an 0.8 custom error):
    /// `NotAgent()` (recipient, mint caller or collect recipient),
    /// `NotAgentOwnerOrCaller()`, `NotAgentTransfer()`,
    /// `AssetRegistryHasNoCode()`.
    /// Keeping selectors instead of strings is required to fit EIP-170.
    bytes4 private constant ERR_NOT_AGENT = bytes4(keccak256('NotAgent()'));
    bytes4 private constant ERR_OWNER_CALLER = bytes4(keccak256('NotAgentOwnerOrCaller()'));
    bytes4 private constant ERR_TRANSFER = bytes4(keccak256('NotAgentTransfer()'));
    bytes4 private constant ERR_ASSET_REGISTRY = bytes4(keccak256('AssetRegistryHasNoCode()'));

    constructor(
        address _factory,
        address _WETH9,
        address _tokenDescriptor_,
        address _assetRegistry
    ) ERC721Permit('Agentswap Positions NFT-V1', 'AGS-V3-POS', '1') PeripheryImmutableState(_factory, _WETH9) {
        uint256 registryCodeSize;
        assembly {
            registryCodeSize := extcodesize(_assetRegistry)
        }
        _require(registryCodeSize > 0, ERR_ASSET_REGISTRY);
        assetRegistry = _assetRegistry;
        _tokenDescriptor = _tokenDescriptor_;
    }

    /// @notice Returns the transfer policy for `token`, or `address(0)` when the
    /// token is not a registered gated asset (e.g. a quote token).
    /// @dev Per-token, not global: a token with a different approved policy
    /// version is resolved through its own registry entry.
    function policyOfToken(address token) public view returns (address) {
        if (!IGatedAssetRegistry(assetRegistry).isRegistered(token)) return address(0);
        return IGatedAssetRegistry(assetRegistry).policyOf(token);
    }

    /// @notice Whether `to` may receive gated liquidity/positions for `token`.
    /// @dev Public (unregistered) tokens are unrestricted. A gated token only
    /// accepts agents: a policy member with category `NONE`. Any facility
    /// category (POOL/LP_MANAGER/FEE_RECIPIENT/CUSTODY/PURPOSE) is rejected
    /// even if the policy reports it as a member.
    function isAllowedRecipient(address token, address to) public view returns (bool) {
        address policy = policyOfToken(token);
        return policy == address(0) || _isAgent(policy, to);
    }

    /// @notice Whether position `tokenId` may move `from` -> `to`.
    /// @dev `from == address(0)` (mint) and `to == address(0)` (burn) skip that
    /// side. Both sides must be agents. Every gated token in the position is
    /// checked, so a gated/gated position requires both policies to pass.
    function isAllowedTransfer(
        uint256 tokenId,
        address from,
        address to
    ) public view returns (bool) {
        uint80 poolId = _positions[tokenId].poolId;
        if (poolId == 0) return false;
        PoolAddress.PoolKey storage poolKey = _poolIdToPoolKey[poolId];
        return
            _isAllowedTransfer(poolKey.token0, from, to) &&
            _isAllowedTransfer(poolKey.token1, from, to);
    }

    /// @inheritdoc INonfungiblePositionManager
    function positions(uint256 tokenId)
        external
        view
        override
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        Position memory position = _positions[tokenId];
        require(position.poolId != 0, 'Invalid token ID');
        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        return (
            position.nonce,
            position.operator,
            poolKey.token0,
            poolKey.token1,
            poolKey.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    /// @dev Caches a pool key
    function cachePoolKey(address pool, PoolAddress.PoolKey memory poolKey) private returns (uint80 poolId) {
        poolId = _poolIds[pool];
        if (poolId == 0) {
            _poolIds[pool] = (poolId = _nextPoolId++);
            _poolIdToPoolKey[poolId] = poolKey;
        }
    }

    /// @inheritdoc INonfungiblePositionManager
    function mint(MintParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        // Gated LP is Agent-only. Check the NFT recipient and the payer/caller
        // against every gated token in the pool before addLiquidity (and thus
        // before any tokens move or a position is created).
        _require(
            isAllowedRecipient(params.token0, params.recipient) &&
                isAllowedRecipient(params.token1, params.recipient),
            ERR_NOT_AGENT
        );
        _require(
            isAllowedRecipient(params.token0, msg.sender) && isAllowedRecipient(params.token1, msg.sender),
            ERR_NOT_AGENT
        );

        IUniswapV3Pool pool;
        (liquidity, amount0, amount1, pool) = addLiquidity(
            AddLiquidityParams({
                token0: params.token0,
                token1: params.token1,
                fee: params.fee,
                recipient: address(this),
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min
            })
        );

        _mint(params.recipient, (tokenId = _nextId++));

        bytes32 positionKey = PositionKey.compute(address(this), params.tickLower, params.tickUpper);
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);

        // idempotent set
        uint80 poolId =
            cachePoolKey(
                address(pool),
                PoolAddress.PoolKey({token0: params.token0, token1: params.token1, fee: params.fee})
            );

        _positions[tokenId] = Position({
            nonce: 0,
            operator: address(0),
            poolId: poolId,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: feeGrowthInside0LastX128,
            feeGrowthInside1LastX128: feeGrowthInside1LastX128,
            tokensOwed0: 0,
            tokensOwed1: 0
        });

        emit IncreaseLiquidity(tokenId, liquidity, amount0, amount1);
    }

    modifier isAuthorizedForToken(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId), 'Not approved');
        _;
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, IERC721Metadata) returns (string memory) {
        require(_exists(tokenId));
        return INonfungibleTokenPositionDescriptor(_tokenDescriptor).tokenURI(this, tokenId);
    }

    // save bytecode by removing implementation of unused method
    function baseURI() public pure override returns (string memory) {}

    /// @inheritdoc INonfungiblePositionManager
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        Position storage position = _positions[params.tokenId];

        // Owner and caller must be agents for every gated token in the position.
        _requireOwnerAndCaller(params.tokenId);

        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];

        IUniswapV3Pool pool;
        (liquidity, amount0, amount1, pool) = addLiquidity(
            AddLiquidityParams({
                token0: poolKey.token0,
                token1: poolKey.token1,
                fee: poolKey.fee,
                tickLower: position.tickLower,
                tickUpper: position.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                recipient: address(this)
            })
        );

        bytes32 positionKey = PositionKey.compute(address(this), position.tickLower, position.tickUpper);

        // this is now updated to the current transaction
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);

        position.tokensOwed0 += uint128(
            FullMath.mulDiv(
                feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                position.liquidity,
                FixedPoint128.Q128
            )
        );
        position.tokensOwed1 += uint128(
            FullMath.mulDiv(
                feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                position.liquidity,
                FixedPoint128.Q128
            )
        );

        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        position.liquidity += liquidity;

        emit IncreaseLiquidity(params.tokenId, liquidity, amount0, amount1);
    }

    /// @inheritdoc INonfungiblePositionManager
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        override
        isAuthorizedForToken(params.tokenId)
        checkDeadline(params.deadline)
        returns (uint256 amount0, uint256 amount1)
    {
        // Owner and caller must be agents for every gated token; the ERC721
        // authorization check above still applies to the caller.
        _requireOwnerAndCaller(params.tokenId);

        require(params.liquidity > 0);
        Position storage position = _positions[params.tokenId];

        uint128 positionLiquidity = position.liquidity;
        require(positionLiquidity >= params.liquidity);

        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));
        (amount0, amount1) = pool.burn(position.tickLower, position.tickUpper, params.liquidity);

        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, 'Price slippage check');

        bytes32 positionKey = PositionKey.compute(address(this), position.tickLower, position.tickUpper);
        // this is now updated to the current transaction
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);

        position.tokensOwed0 +=
            uint128(amount0) +
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                    positionLiquidity,
                    FixedPoint128.Q128
                )
            );
        position.tokensOwed1 +=
            uint128(amount1) +
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                    positionLiquidity,
                    FixedPoint128.Q128
                )
            );

        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        // subtraction is safe because we checked positionLiquidity is gte params.liquidity
        position.liquidity = positionLiquidity - params.liquidity;

        emit DecreaseLiquidity(params.tokenId, params.liquidity, amount0, amount1);
    }

    /// @inheritdoc INonfungiblePositionManager
    function collect(CollectParams calldata params)
        external
        payable
        override
        isAuthorizedForToken(params.tokenId)
        returns (uint256 amount0, uint256 amount1)
    {
        require(params.amount0Max > 0 || params.amount1Max > 0);
        // allow collecting to the nft position manager address with address 0
        address recipient = params.recipient == address(0) ? address(this) : params.recipient;

        // Owner, caller and the collect recipient must be agents for every
        // gated token. address(0) resolves to this NPM (an LP_MANAGER), never
        // an agent, so the zero-recipient shortcut is closed for gated tokens.
        _requireOwnerAndCaller(params.tokenId);
        _require(isAllowedTransfer(params.tokenId, recipient, recipient), ERR_NOT_AGENT);

        Position storage position = _positions[params.tokenId];

        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];

        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));

        (uint128 tokensOwed0, uint128 tokensOwed1) = (position.tokensOwed0, position.tokensOwed1);

        // trigger an update of the position fees owed and fee growth snapshots if it has any liquidity
        if (position.liquidity > 0) {
            pool.burn(position.tickLower, position.tickUpper, 0);
            (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) =
                pool.positions(PositionKey.compute(address(this), position.tickLower, position.tickUpper));

            tokensOwed0 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                    position.liquidity,
                    FixedPoint128.Q128
                )
            );
            tokensOwed1 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                    position.liquidity,
                    FixedPoint128.Q128
                )
            );

            position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
            position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        }

        // compute the arguments to give to the pool#collect method
        (uint128 amount0Collect, uint128 amount1Collect) =
            (
                params.amount0Max > tokensOwed0 ? tokensOwed0 : params.amount0Max,
                params.amount1Max > tokensOwed1 ? tokensOwed1 : params.amount1Max
            );

        // the actual amounts collected are returned
        (amount0, amount1) = pool.collect(
            recipient,
            position.tickLower,
            position.tickUpper,
            amount0Collect,
            amount1Collect
        );

        // sometimes there will be a few less wei than expected due to rounding down in core, but we just subtract the full amount expected
        // instead of the actual amount so we can burn the token
        (position.tokensOwed0, position.tokensOwed1) = (tokensOwed0 - amount0Collect, tokensOwed1 - amount1Collect);

        emit Collect(params.tokenId, recipient, amount0Collect, amount1Collect);
    }

    /// @inheritdoc INonfungiblePositionManager
    function burn(uint256 tokenId) external payable override isAuthorizedForToken(tokenId) {
        Position storage position = _positions[tokenId];
        require(position.liquidity == 0 && position.tokensOwed0 == 0 && position.tokensOwed1 == 0, 'Not cleared');
        _requireOwnerAndCaller(tokenId);
        // Burn the NFT before deleting the position storage: _beforeTokenTransfer
        // resolves the position's gated tokens, and a final owner gate is applied
        // there as well. The cleared check above already passed.
        _burn(tokenId);
        delete _positions[tokenId];
    }

    /// @dev Mint (`from == address(0)`) is prechecked in `mint` before
    /// addLiquidity. Burns and transfers are checked here for every gated token
    /// in the position; a facility is never valid on either side. A transfer's
    /// caller must also be an agent: an approved non-agent marketplace operator
    /// cannot move a gated LP NFT between agents.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal view override {
        if (from == address(0)) return;
        _require(isAllowedTransfer(tokenId, from, to), ERR_TRANSFER);
        if (to != address(0)) {
            _require(isAllowedTransfer(tokenId, msg.sender, msg.sender), ERR_TRANSFER);
        }
    }

    /// @dev Emits the selector directly (no Error(string) payload); see the
    /// gate error list above. 0.7.6 custom-error equivalent.
    function _require(bool condition, bytes4 selector) private pure {
        assembly {
            if iszero(condition) {
                mstore(0, selector)
                revert(0, 4)
            }
        }
    }

    /// @dev Agent = policy member with category `NONE`; facilities are never
    /// agents regardless of membership.
    function _isAgent(address policy, address account) private view returns (bool) {
        return
            IGatedTransferPolicy(policy).isMember(account) &&
            IGatedTransferPolicy(policy).categoryOf(account) == FacilityCategory.NONE;
    }

    /// @dev One token side of `isAllowedTransfer`; zero sides (mint/burn) skip.
    function _isAllowedTransfer(
        address token,
        address from,
        address to
    ) private view returns (bool) {
        address policy = policyOfToken(token);
        if (policy == address(0)) return true;
        if (from != address(0) && !_isAgent(policy, from)) return false;
        if (to != address(0) && !_isAgent(policy, to)) return false;
        return true;
    }

    /// @dev Owner and caller must both be agents under every gated token.
    function _requireOwnerAndCaller(uint256 tokenId) private view {
        _require(isAllowedTransfer(tokenId, ownerOf(tokenId), msg.sender), ERR_OWNER_CALLER);
    }

    function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
        return uint256(_positions[tokenId].nonce++);
    }

    /// @inheritdoc IERC721
    function getApproved(uint256 tokenId) public view override(ERC721, IERC721) returns (address) {
        require(_exists(tokenId), 'ERC721: approved query for nonexistent token');

        return _positions[tokenId].operator;
    }

    /// @dev Overrides _approve to use the operator in the position, which is packed with the position permit nonce
    function _approve(address to, uint256 tokenId) internal override(ERC721) {
        _positions[tokenId].operator = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }
}
