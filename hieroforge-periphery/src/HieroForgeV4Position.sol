// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {HTS_ADDRESS} from "hedera-forking/HtsSystemContract.sol";
import {IHederaTokenService} from "hedera-forking/IHederaTokenService.sol";
import {HederaResponseCodes} from "hedera-forking/HederaResponseCodes.sol";
import {IERC721} from "hedera-forking/IERC721.sol";
import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";
import {BaseActionsRouter} from "./base/BaseActionsRouter.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {Currency} from "hieroforge-core/types/Currency.sol";
import {BalanceDelta} from "hieroforge-core/types/BalanceDelta.sol";
import {IERC20Minimal} from "hieroforge-core/interfaces/IERC20Minimal.sol";
import {ModifyLiquidityParams} from "hieroforge-core/types/ModifyLiquidityParams.sol";
import {SafeCast} from "hieroforge-core/libraries/SafeCast.sol";
import {Actions} from "./libraries/Actions.sol";
import {ActionConstants} from "./libraries/ActionConstants.sol";
import {CalldataDecoder} from "./libraries/CalldataDecoder.sol";
import {PositionInfo, PositionInfoLibrary} from "./types/PositionInfo.sol";
import {IPoolInitializer_v4} from "./interfaces/IPoolInitializer_v4.sol";
import {Multicall_v4} from "./base/Multicall_v4.sol";

/// @title HieroForgeV4Position
/// @notice Position manager implementation (separate from `PositionManager`) with the same BaseActionsRouter + Multicall_v4 flow,
///         using an HTS NFT collection to represent position ownership (one HTS serial per position).
///         This contract mirrors the PositionManager core logic so tests and behavior stay in sync while swapping ERC721 for HTS.
contract HieroForgeV4Position is IPositionManager, IPoolInitializer_v4, Multicall_v4, BaseActionsRouter {
    using CalldataDecoder for bytes;
    using SafeCast for uint256;
    using SafeCast for int256;

    /// @dev When non-zero, the address that initiated modifyLiquidities (used in unlock callback so msgSender() is correct)
    address private _executor;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint256 public nextTokenId = 1;

    /// @dev Position info per token ID (poolId, tickLower, tickUpper, hasSubscriber)
    mapping(uint256 tokenId => PositionInfo) public positionInfo;

    /// @dev Pool key per truncated pool ID (used when tickSpacing is 0 to detect "not set")
    mapping(bytes25 poolId => PoolKey) public poolKeys;

    /// @dev Liquidity per token ID (tracked so burn can remove all remaining liquidity)
    mapping(uint256 tokenId => uint128) public positionLiquidity;

    /// @dev Reverted when position info or pool key is missing for a token
    error TokenDoesNotExist();

    /// @dev Reverted when slippage limits are exceeded
    error SlippageCheckFailed(uint128 amount0, uint128 amount1, uint128 limit0, uint128 limit1);

    /// @notice HTS NFT collection address (optional; set after createCollection)
    address public htsTokenAddress;
    string public constant HTS_NAME = "HieroForge V4 Position";
    string public constant HTS_SYMBOL = "HFV4P";

    bytes private constant DEFAULT_METADATA = hex"01";

    /// @notice Contract owner (controls HTS collection)
    address public owner;
    /// @notice Hedera ECDSA account used for token expiry autoRenew. Must match PRIVATE_KEY signer so precompile signature is valid.
    address public operatorAccount;

    event NFTCollectionCreated(address indexed token);
    event NFTMinted(address indexed to, uint256 indexed tokenId);

    error OnlyOwner();
    error HtsCreationFailed();
    error HtsMintFailed();
    error NotPositionOwner();
    error CollectionAlreadyCreated();
    error CollectionNotCreated();

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(IPoolManager _poolManager, address _operatorAccount) BaseActionsRouter(_poolManager) {
        owner = msg.sender;
        operatorAccount = _operatorAccount;
    }

    /// @notice Reverts if the deadline has passed
    /// @param deadline The timestamp at which the call is no longer valid, passed in by the caller
    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert DeadlinePassed(deadline);
        _;
    }

    /// @notice Returns the address that initiated the current flow. During unlock callback, returns the modifyLiquidities caller; otherwise msg.sender.
    function msgSender() public view virtual override returns (address) {
        if (_executor != address(0)) return _executor;
        return msg.sender;
    }

    /// @dev Read current owner of an HTS position NFT via the ERC721 mirror interface.
    function _positionOwner(uint256 tokenId) internal view returns (address) {
        if (htsTokenAddress == address(0)) revert CollectionNotCreated();
        return IERC721(htsTokenAddress).ownerOf(tokenId);
    }


    /// @dev Returns true if spender is owner or approved for the tokenId (ERC721-style logic).
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = _positionOwner(tokenId);
        return (spender == owner ||
            IERC721(htsTokenAddress).getApproved(tokenId) == spender ||
            IERC721(htsTokenAddress).isApprovedForAll(owner, spender));
    }

    /// @dev Restrict actions to the HTS NFT owner or approved (ERC721-style behavior).
    modifier onlyPositionOwnerOrApproved(uint256 tokenId) {
        if (!_isApprovedOrOwner(msgSender(), tokenId)) revert NotPositionOwner();
        _;
    }

    /// @notice ERC721-style ownerOf for a position tokenId, backed by the HTS NFT collection.
    function ownerOf(uint256 tokenId) external view returns (address) {
        return _positionOwner(tokenId);
    }

    /// @notice ERC721-style balanceOf for a user, backed by the HTS NFT collection.
    function balanceOf(address account) external view returns (uint256) {
        if (htsTokenAddress == address(0)) revert CollectionNotCreated();
        return IERC721(htsTokenAddress).balanceOf(account);
    }

    /// @notice ERC721-style approve for compatibility with existing tests and tooling.
    ///         This delegates to the underlying HTS ERC721 mirror contract.
    function approve(address to, uint256 tokenId) external {
        if (htsTokenAddress == address(0)) revert CollectionNotCreated();
        // Caller must be the HTS owner or approved; HTS precompile enforces this.
        IERC721(htsTokenAddress).approve(to, tokenId);
    }

    /// @inheritdoc IPoolInitializer_v4
    /// @notice Initialize a pool on the PoolManager (no-op if already initialized; returns type(int24).max).
    function initializePool(PoolKey calldata key, uint160 sqrtPriceX96) external payable override returns (int24) {
        try poolManager.initialize(key, sqrtPriceX96) returns (int24 tick) {
            return tick;
        } catch {
            return type(int24).max;
        }
    }

    /// @inheritdoc IPositionManager
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline)
        external
        payable
        override
        checkDeadline(deadline)
    {
        _executor = msg.sender;
        _executeActions(unlockData);
        _executor = address(0);
    }

    function _handleAction(uint256 action, bytes calldata params) internal virtual override {
        if (action < Actions.SETTLE) {
            if (action == Actions.INCREASE_LIQUIDITY) {
                (uint256 tokenId, uint256 liquidity, uint128 amount0Max, uint128 amount1Max, bytes calldata hookData) =
                    params.decodeModifyLiquidityParams();
                _increase(tokenId, liquidity, amount0Max, amount1Max, hookData);
                return;
            } else if (action == Actions.DECREASE_LIQUIDITY) {
                (uint256 tokenId, uint256 liquidity, uint128 amount0Min, uint128 amount1Min, bytes calldata hookData) =
                    params.decodeModifyLiquidityParams();
                _decrease(tokenId, liquidity, amount0Min, amount1Min, hookData);
                return;
            } else if (action == Actions.MINT_POSITION) {
                (
                    PoolKey memory poolKey,
                    int24 tickLower,
                    int24 tickUpper,
                    uint256 liquidity,
                    uint128 amount0Max,
                    uint128 amount1Max,
                    address owner_,
                    bytes calldata hookData
                ) = params.decodeMintParams();
                _mint(poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, owner_, hookData);
                return;
            } else if (action == Actions.BURN_POSITION) {
                (uint256 tokenId, uint128 amount0Min, uint128 amount1Min, bytes calldata hookData) =
                    params.decodeBurnParams();
                _burnPosition(tokenId, amount0Min, amount1Min, hookData);
                return;
            } else if (action == Actions.INCREASE_LIQUIDITY_FROM_DELTAS) {
                (uint256 tokenId, uint256 liquidity, uint128 amount0Max, uint128 amount1Max, bytes calldata hookData) =
                    params.decodeModifyLiquidityParams();
                _increaseFromDeltas(tokenId, liquidity, amount0Max, amount1Max, hookData);
                return;
            } else if (action == Actions.MINT_POSITION_FROM_DELTAS) {
                (
                    PoolKey memory poolKey,
                    int24 tickLower,
                    int24 tickUpper,
                    uint256 liquidity,
                    uint128 amount0Max,
                    uint128 amount1Max,
                    address owner_,
                    bytes calldata hookData
                ) = params.decodeMintParams();
                _mintFromDeltas(poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, owner_, hookData);
                return;
            }
        } else {
            // ── Settlement actions (compose with FROM_DELTAS) ──
            if (action == Actions.SETTLE) {
                (Currency currency, uint256 amount, bool payerIsUser) = params.decodeCurrencyUint256AndBool();
                // Map OPEN_DELTA to actual debt
                if (amount == ActionConstants.OPEN_DELTA) {
                    int256 delta = poolManager.currencyDelta(address(this), currency);
                    if (delta >= 0) return; // no debt to settle
                    amount = uint256(-delta);
                }
                if (payerIsUser) {
                    _settleFromUser(currency, amount);
                } else {
                    _settleCurrency(currency, amount);
                }
                return;
            } else if (action == Actions.SETTLE_PAIR) {
                (Currency c0, Currency c1) = params.decodeCurrencyPair();
                int256 d0 = poolManager.currencyDelta(address(this), c0);
                int256 d1 = poolManager.currencyDelta(address(this), c1);
                if (d0 < 0) _settleFromUser(c0, uint256(-d0));
                if (d1 < 0) _settleFromUser(c1, uint256(-d1));
                return;
            } else if (action == Actions.TAKE) {
                (Currency currency, address recipient, uint256 amount) = params.decodeCurrencyAddressAndUint256();
                if (amount == ActionConstants.OPEN_DELTA) {
                    int256 delta = poolManager.currencyDelta(address(this), currency);
                    if (delta <= 0) return; // no credit to take
                    amount = uint256(delta);
                }
                poolManager.take(currency, recipient, amount);
                return;
            } else if (action == Actions.TAKE_PAIR) {
                (Currency c0, Currency c1, address recipient) = params.decodeCurrencyPairAndAddress();
                int256 d0 = poolManager.currencyDelta(address(this), c0);
                int256 d1 = poolManager.currencyDelta(address(this), c1);
                if (d0 > 0) poolManager.take(c0, recipient, uint256(d0));
                if (d1 > 0) poolManager.take(c1, recipient, uint256(d1));
                return;
            } else if (action == Actions.CLOSE_CURRENCY) {
                Currency currency = params.decodeCurrency();
                int256 delta = poolManager.currencyDelta(address(this), currency);
                if (delta < 0) {
                    _settleFromUser(currency, uint256(-delta));
                } else if (delta > 0) {
                    poolManager.take(currency, msgSender(), uint256(delta));
                }
                return;
            }
        }
        revert UnsupportedAction(action);
    }

    /// @dev Returns the pool key and position info for a token. Reverts if token does not exist or pool not set.
    function getPoolAndPositionInfo(uint256 tokenId) internal view returns (PoolKey memory poolKey, PositionInfo info) {
        info = positionInfo[tokenId];
        poolKey = poolKeys[info.poolId()];
        if (poolKey.tickSpacing == 0) revert TokenDoesNotExist();
    }

    /// @dev Calling increase with 0 liquidity will credit the caller with any underlying fees of the position
    function _increase(
        uint256 tokenId,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        bytes calldata hookData
    ) internal onlyPositionOwnerOrApproved(tokenId) {
        (PoolKey memory poolKey, PositionInfo info) = getPoolAndPositionInfo(tokenId);

        // Note: The tokenId is used as the salt for this position, so every minted position has unique storage in the pool manager.
        (BalanceDelta liquidityDelta, BalanceDelta feesAccrued) =
            _modifyLiquidity(info, poolKey, int256(liquidity), bytes32(tokenId), hookData);
        _settlePoolDeltas(poolKey, liquidityDelta, feesAccrued);

        // Track position liquidity
        positionLiquidity[tokenId] += uint128(liquidity);

        // Slippage check: principal amounts (excluding fee credits) must not exceed max
        _validateMaxIn(liquidityDelta, feesAccrued, amount0Max, amount1Max);
    }

    function _mint(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        address owner_,
        bytes calldata hookData
    ) internal {
        if (htsTokenAddress == address(0)) revert CollectionNotCreated();

        // Mint an HTS NFT for this position and transfer it to the owner.
        bytes[] memory metadata = new bytes[](1);
        metadata[0] = DEFAULT_METADATA;

        (int64 rc, , int64[] memory serials) =
            IHederaTokenService(HTS_ADDRESS).mintToken(htsTokenAddress, 0, metadata);
        if (rc != HederaResponseCodes.SUCCESS) revert HtsMintFailed();

        uint256 tokenId = uint256(uint64(serials[0]));
        IERC721(htsTokenAddress).transferFrom(address(this), owner_, tokenId);

        // Initialize the position info
        PositionInfo info = PositionInfoLibrary.initialize(poolKey, tickLower, tickUpper);
        positionInfo[tokenId] = info;

        // Store the poolKey if it is not already stored.
        // On UniswapV4, the minimum tick spacing is 1, which means that if the tick spacing is 0, the pool key has not been set.
        bytes25 poolId = info.poolId();
        if (poolKeys[poolId].tickSpacing == 0) {
            poolKeys[poolId] = poolKey;
        }

        (BalanceDelta liquidityDelta, BalanceDelta feesAccrued) =
            _modifyLiquidity(info, poolKey, int256(liquidity), bytes32(tokenId), hookData);
        _settlePoolDeltas(poolKey, liquidityDelta, feesAccrued);

        // Track position liquidity
        positionLiquidity[tokenId] = uint128(liquidity);

        // Slippage check: amounts deposited must not exceed max
        _validateMaxIn(liquidityDelta, feesAccrued, amount0Max, amount1Max);
    }

    // ─── FROM_DELTAS variants (no auto-settlement — deltas stay open for explicit SETTLE/TAKE) ───

    /// @dev Like _increase but does NOT settle — the caller must follow with SETTLE actions
    function _increaseFromDeltas(
        uint256 tokenId,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        bytes calldata hookData
    ) internal onlyPositionOwnerOrApproved(tokenId) {
        (PoolKey memory poolKey, PositionInfo info) = getPoolAndPositionInfo(tokenId);
        (BalanceDelta liquidityDelta, BalanceDelta feesAccrued) =
            _modifyLiquidity(info, poolKey, int256(liquidity), bytes32(tokenId), hookData);

        // Track position liquidity
        positionLiquidity[tokenId] += uint128(liquidity);

        // Slippage check
        _validateMaxIn(liquidityDelta, feesAccrued, amount0Max, amount1Max);
        // NOTE: no _settlePoolDeltas — caller must settle via SETTLE / SETTLE_PAIR / CLOSE_CURRENCY
    }

    /// @dev Like _mint but does NOT settle — the caller must follow with SETTLE actions
    function _mintFromDeltas(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        address owner_,
        bytes calldata hookData
    ) internal {
        if (htsTokenAddress == address(0)) revert CollectionNotCreated();

        // Mint an HTS NFT for this position and transfer it to the owner.
        bytes[] memory metadata = new bytes[](1);
        metadata[0] = DEFAULT_METADATA;

        (int64 rc, , int64[] memory serials) =
            IHederaTokenService(HTS_ADDRESS).mintToken(htsTokenAddress, 0, metadata);
        if (rc != HederaResponseCodes.SUCCESS) revert HtsMintFailed();

        uint256 tokenId = uint256(uint64(serials[0]));
        IERC721(htsTokenAddress).transferFrom(address(this), owner_, tokenId);

        PositionInfo info = PositionInfoLibrary.initialize(poolKey, tickLower, tickUpper);
        positionInfo[tokenId] = info;

        bytes25 poolId = info.poolId();
        if (poolKeys[poolId].tickSpacing == 0) {
            poolKeys[poolId] = poolKey;
        }

        (BalanceDelta liquidityDelta, BalanceDelta feesAccrued) =
            _modifyLiquidity(info, poolKey, int256(liquidity), bytes32(tokenId), hookData);

        positionLiquidity[tokenId] = uint128(liquidity);

        // Slippage check
        _validateMaxIn(liquidityDelta, feesAccrued, amount0Max, amount1Max);
        // NOTE: no _settlePoolDeltas — caller must settle via SETTLE / SETTLE_PAIR / CLOSE_CURRENCY
    }

    /// @dev Settle currency by pulling from the user (msgSender) via transferFrom
    function _settleFromUser(Currency currency, uint256 amount) internal {
        if (Currency.unwrap(currency) == address(0)) {
            poolManager.settle{value: amount}();
            return;
        }
        poolManager.sync(currency);
        require(
            IERC20Minimal(Currency.unwrap(currency)).transferFrom(msgSender(), address(poolManager), amount),
            "HieroForgeV4Position: transferFrom failed"
        );
        poolManager.settle();
    }

    /// @dev Settles negative balance deltas with the pool manager (sync + transfer + settle)
    function _settlePoolDeltas(PoolKey memory poolKey, BalanceDelta liquidityDelta, BalanceDelta feesAccrued) internal {
        int128 a0 = liquidityDelta.amount0() + feesAccrued.amount0();
        int128 a1 = liquidityDelta.amount1() + feesAccrued.amount1();
        if (a0 < 0) _settleCurrency(poolKey.currency0, uint256(uint128(-a0)));
        if (a1 < 0) _settleCurrency(poolKey.currency1, uint256(uint128(-a1)));
    }

    function _settleCurrency(Currency currency, uint256 amount) internal {
        if (Currency.unwrap(currency) == address(0)) {
            poolManager.settle{value: amount}();
            return;
        }
        poolManager.sync(currency);
        require(
            IERC20Minimal(Currency.unwrap(currency)).transfer(address(poolManager), amount),
            "HieroForgeV4Position: transfer failed"
        );
        poolManager.settle();
    }

    /// @dev if there is a subscriber attached to the position, this function will notify the subscriber
    function _modifyLiquidity(
        PositionInfo info,
        PoolKey memory poolKey,
        int256 liquidityChange,
        bytes32 salt,
        bytes calldata hookData
    ) internal returns (BalanceDelta liquidityDelta, BalanceDelta feesAccrued) {
        (liquidityDelta, feesAccrued) = poolManager.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: info.tickLower(), tickUpper: info.tickUpper(), liquidityDelta: liquidityChange, salt: salt
            }),
            hookData
        );
        // NOTE: subscriber notifications will be implemented later, mirroring PositionManager
    }

    /// @dev Calling decrease with 0 liquidity will credit the caller with any underlying fees of the position
    function _decrease(
        uint256 tokenId,
        uint256 liquidity,
        uint128 amount0Min,
        uint128 amount1Min,
        bytes calldata hookData
    ) internal onlyPositionOwnerOrApproved(tokenId) {
        (PoolKey memory poolKey, PositionInfo info) = getPoolAndPositionInfo(tokenId);

        // Note: the tokenId is used as the salt.
        (BalanceDelta liquidityDelta, BalanceDelta feesAccrued) =
            _modifyLiquidity(info, poolKey, -int256(liquidity), bytes32(tokenId), hookData);
        _takePoolDeltas(poolKey, liquidityDelta, feesAccrued);

        // Track position liquidity
        positionLiquidity[tokenId] -= uint128(liquidity);

        // Slippage check: principal amounts returned must meet minimums
        _validateMinOut(liquidityDelta, feesAccrued, amount0Min, amount1Min);
    }

    /// @dev Burns a position NFT. The position must have 0 liquidity remaining.
    /// Collects any outstanding fees and deletes position info. The HTS NFT remains but no longer maps to a live position.
    function _burnPosition(uint256 tokenId, uint128 amount0Min, uint128 amount1Min, bytes calldata hookData)
        internal
        onlyPositionOwnerOrApproved(tokenId)
    {
        (PoolKey memory poolKey, PositionInfo info) = getPoolAndPositionInfo(tokenId);

        uint128 posLiquidity = positionLiquidity[tokenId];

        // If there is remaining liquidity, decrease it all first
        BalanceDelta liquidityDelta;
        BalanceDelta feesAccrued;
        if (posLiquidity > 0) {
            (liquidityDelta, feesAccrued) =
                _modifyLiquidity(info, poolKey, -int256(uint256(posLiquidity)), bytes32(tokenId), hookData);
        } else {
            // Even with 0 liquidity, collect any remaining fees by calling modifyLiquidity with 0 delta
            (liquidityDelta, feesAccrued) = _modifyLiquidity(info, poolKey, 0, bytes32(tokenId), hookData);
        }

        // Send tokens back to caller
        _takePoolDeltas(poolKey, liquidityDelta, feesAccrued);

        // Slippage check on amounts out
        _validateMinOut(liquidityDelta, feesAccrued, amount0Min, amount1Min);

        // Clear position state
        delete positionLiquidity[tokenId];
        positionInfo[tokenId] = PositionInfoLibrary.EMPTY_POSITION_INFO;
    }

    /// @dev Takes positive balance deltas from the pool manager (tokens out to executor)
    function _takePoolDeltas(PoolKey memory poolKey, BalanceDelta liquidityDelta, BalanceDelta feesAccrued) internal {
        int128 a0 = liquidityDelta.amount0() + feesAccrued.amount0();
        int128 a1 = liquidityDelta.amount1() + feesAccrued.amount1();
        address to = msgSender();
        if (a0 > 0) poolManager.take(poolKey.currency0, to, uint256(uint128(a0)));
        if (a1 > 0) poolManager.take(poolKey.currency1, to, uint256(uint128(a1)));
    }

    /// @dev Validates that principal amounts deposited (excluding fee credits) don't exceed slippage limits
    function _validateMaxIn(
        BalanceDelta liquidityDelta,
        BalanceDelta feesAccrued,
        uint128 amount0Max,
        uint128 amount1Max
    ) internal pure {
        // Principal = liquidityDelta - feesAccrued (for adds, liquidityDelta is negative = tokens in)
        int128 principal0 = liquidityDelta.amount0() - feesAccrued.amount0();
        int128 principal1 = liquidityDelta.amount1() - feesAccrued.amount1();
        // Amounts in are negative deltas; check absolute value against max
        uint128 abs0 = principal0 < 0 ? uint128(-principal0) : 0;
        uint128 abs1 = principal1 < 0 ? uint128(-principal1) : 0;
        if (abs0 > amount0Max || abs1 > amount1Max) {
            revert SlippageCheckFailed(abs0, abs1, amount0Max, amount1Max);
        }
    }

    /// @dev Validates that principal amounts received (excluding fees) meet minimum slippage requirements
    function _validateMinOut(
        BalanceDelta liquidityDelta,
        BalanceDelta feesAccrued,
        uint128 amount0Min,
        uint128 amount1Min
    ) internal pure {
        // Principal = liquidityDelta - feesAccrued (for removes, liquidityDelta is positive = tokens out)
        int128 principal0 = liquidityDelta.amount0() - feesAccrued.amount0();
        int128 principal1 = liquidityDelta.amount1() - feesAccrued.amount1();
        // Amounts out are positive deltas
        uint128 out0 = principal0 > 0 ? uint128(principal0) : 0;
        uint128 out1 = principal1 > 0 ? uint128(principal1) : 0;
        if (out0 < amount0Min || out1 < amount1Min) {
            revert SlippageCheckFailed(out0, out1, amount0Min, amount1Min);
        }
    }

    /// @notice One-time HTS NFT collection creation. Call from deploy script with {value: HTS_VALUE, gas: HTS_CREATE_GAS_LIMIT}.
    ///         expiry.autoRenewAccount must be the Hedera ECDSA account that signs the tx (operatorAccount).
    function createCollection() external payable onlyOwner {
        if (htsTokenAddress != address(0)) revert CollectionAlreadyCreated();

        IHederaTokenService.KeyValue memory contractKey;
        contractKey.contractId = address(this);

        IHederaTokenService.HederaToken memory token;
        token.name = HTS_NAME;
        token.symbol = HTS_SYMBOL;
        token.treasury = address(this);
        token.memo = "";
        token.tokenSupplyType = true;
        // Allow the maximum possible number of HTS NFTs (positions) in this collection.
        token.maxSupply = type(int64).max;
        token.freezeDefault = false;
        token.tokenKeys = new IHederaTokenService.TokenKey[](2);
        token.tokenKeys[0] = IHederaTokenService.TokenKey(0x1, contractKey);   // ADMIN
        token.tokenKeys[1] = IHederaTokenService.TokenKey(0x10, contractKey);  // SUPPLY
        token.expiry = IHederaTokenService.Expiry(0, address(0), 8_000_000);

        (int64 rc, address created) = IHederaTokenService(HTS_ADDRESS).createNonFungibleToken{value: msg.value}(token);
        if (rc != HederaResponseCodes.SUCCESS) revert HtsCreationFailed();

        htsTokenAddress = created;
        emit NFTCollectionCreated(created);
    }

    /// @notice Mint an HTS NFT to a recipient (standalone HTS mint; not a pool position). For pool positions use modifyLiquidities(MINT_POSITION, ...).
    function mintNFT(address to) external onlyOwner returns (uint256) {
        if (htsTokenAddress == address(0)) revert CollectionNotCreated();

        bytes[] memory metadata = new bytes[](1);
        metadata[0] = DEFAULT_METADATA;

        (int64 rc, , int64[] memory serials) =
            IHederaTokenService(HTS_ADDRESS).mintToken(htsTokenAddress, 0, metadata);
        if (rc != HederaResponseCodes.SUCCESS) revert HtsMintFailed();

        uint256 tokenId = uint256(uint64(serials[0]));
        IERC721(htsTokenAddress).transferFrom(address(this), to, tokenId);

        emit NFTMinted(to, tokenId);
        return tokenId;
    }
}
