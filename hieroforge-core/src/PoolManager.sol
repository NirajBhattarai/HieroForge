// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {PoolId} from "./types/PoolId.sol";
import {Currency, CurrencyDelta, CurrencyLibrary} from "./types/Currency.sol";
import {PoolState} from "./types/PoolState.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {initialPoolState} from "./types/Slot0.sol";
import {ModifyLiquidityParams} from "./types/ModifyLiquidityParams.sol";
import {ModifyLiquidityOperation} from "./types/PoolOperation.sol";
import {SwapParams} from "./types/SwapParams.sol";
import {SwapResult} from "./types/SwapResult.sol";
import {BalanceDelta, toBalanceDelta} from "./types/BalanceDelta.sol";
import {Lock} from "./libraries/Lock.sol";
import {NonzeroDeltaCount} from "./libraries/NonzeroDeltaCount.sol";
import {CustomRevert} from "./libraries/CustomRevert.sol";
import {IUnlockCallback} from "./callback/IUnlockCallback.sol";
import {NoDelegateCall} from "./NoDelegateCall.sol";

using CustomRevert for bytes4;
using CurrencyDelta for Currency;
using CurrencyLibrary for Currency;
using SafeCast for uint256;

/// @notice Thrown when settling an ERC20 currency but msg.value is nonzero
error NonzeroNativeValue();

/// @title PoolManager
/// @notice Holds pool state and implements initialize and swap (Uniswap v4-style)
contract PoolManager is IPoolManager, NoDelegateCall {
    mapping(PoolId id => PoolState) internal _pools;

    bytes32 private constant SYNCED_CURRENCY_SLOT = keccak256("PoolManager.syncedCurrency");
    bytes32 private constant SYNCED_RESERVES_SLOT = keccak256("PoolManager.syncedReserves");

    /// @notice This will revert if the contract is locked
    modifier onlyWhenUnlocked() {
        if (!Lock.isUnlocked()) IPoolManager.ManagerLocked.selector.revertWith();
        _;
    }

    constructor() {}

    /// @inheritdoc IPoolManager
    /// @dev Pools accept any currency combination: ERC20-ERC20, ERC20-HTS, or HTS-HTS. Use TokenClassifier to identify token types.
    function initialize(PoolKey memory key, uint160 sqrtPriceX96)
        external
        override
        noDelegateCall
        returns (int24 tick)
    {
        // Validate that the currencies are sorted in ascending order, ensuring that currency0 is less than currency1.
        // This maintains consistency for all pool identifiers, preventing duplicates with reversed keys.
        // Also, check that the provided tickSpacing in the PoolKey is within the allowed range,
        // which helps to manage pool granularity and ensure protocol safety.
        key.validate();
        PoolId id = key.toId();
        PoolState storage state = _getPool(id);
        if (state.slot0.sqrtPriceX96() != 0) revert PoolAlreadyInitialized();
        (state.slot0, tick, state.feeGrowthGlobal0X128, state.feeGrowthGlobal1X128, state.liquidity) =
            initialPoolState(sqrtPriceX96, key.fee);
        emit Initialize(id, key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks, sqrtPriceX96, tick);
    }

    /// @inheritdoc IPoolManager
    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes calldata hookData)
        external
        override
        onlyWhenUnlocked
        noDelegateCall
        returns (BalanceDelta callerDelta, BalanceDelta feesAccrued)
    {
        // Validate:
        // - currencies are sorted in ascending order (currency0 < currency1) to prevent duplicates with reversed keys
        // - tickSpacing in PoolKey is within the allowed range for safety and granularity of pools
        key.validate();
        PoolId id = key.toId();
        PoolState storage state = _getPool(id);

        ModifyLiquidityOperation memory op = ModifyLiquidityOperation({
            owner: msg.sender,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidityDelta: int128(params.liquidityDelta),
            tickSpacing: key.tickSpacing,
            salt: params.salt
        });
        BalanceDelta principalDelta;
        (principalDelta, feesAccrued) = state.modifyLiquidity(op, hookData);

        // Fee delta and principal delta are both accrued to the caller
        callerDelta = toBalanceDelta(
            principalDelta.amount0() + feesAccrued.amount0(), principalDelta.amount1() + feesAccrued.amount1()
        );
        emit ModifyLiquidity(
            id,
            msg.sender,
            op.owner,
            op.tickLower,
            op.tickUpper,
            op.liquidityDelta,
            callerDelta.amount0(),
            callerDelta.amount1()
        );

        _accountPoolBalanceDelta(key, callerDelta, msg.sender);
    }

    /// @notice Adds a balance delta in a currency for a target address
    function _accountDelta(Currency currency, int128 delta, address target) internal {
        if (delta == 0) return;

        (int256 previous, int256 next) = currency.applyDelta(target, delta);

        if (next == 0) {
            NonzeroDeltaCount.decrement();
        } else if (previous == 0) {
            NonzeroDeltaCount.increment();
        }
    }

    /// @notice Accounts the deltas of 2 currencies to a target address
    function _accountPoolBalanceDelta(PoolKey memory key, BalanceDelta delta, address target) internal {
        _accountDelta(key.currency0, delta.amount0(), target);
        _accountDelta(key.currency1, delta.amount1(), target);
    }

    function _swap(PoolState storage poolState, PoolId id, SwapParams memory params, Currency inputCurrency)
        internal
        returns (BalanceDelta)
    {
        (BalanceDelta delta, uint256 amountToProtocol, uint24 swapFee, SwapResult memory result) =
            poolState.swap(params);

        // event is emitted before the afterSwap call to ensure events are always emitted in order
        emit Swap(
            id,
            msg.sender,
            delta.amount0(),
            delta.amount1(),
            result.sqrtPriceX96,
            result.liquidity,
            result.tick,
            swapFee
        );
        return delta;
    }

    /// @inheritdoc IPoolManager
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        override
        onlyWhenUnlocked
        noDelegateCall
        returns (BalanceDelta swapDelta)
    {
        if (params.amountSpecified == 0) revert IPoolManager.SwapAmountCannotBeZero();
        key.validate();
        PoolId id = key.toId();
        PoolState storage state = _getPool(id);

        Currency inputCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        swapDelta = _swap(state, id, params, inputCurrency);
        _accountPoolBalanceDelta(key, swapDelta, msg.sender);
    }

    /// @inheritdoc IPoolManager
    function unlock(bytes calldata data) external override returns (bytes memory result) {
        if (Lock.isUnlocked()) IPoolManager.AlreadyUnlocked.selector.revertWith();

        Lock.unlock();

        // the caller does everything in this callback, including paying what they owe via calls to settle
        result = IUnlockCallback(msg.sender).unlockCallback(data);

        if (NonzeroDeltaCount.read() != 0) IPoolManager.CurrencyNotSettled.selector.revertWith();
        Lock.lock();
    }

    /// @inheritdoc IPoolManager
    function sync(Currency currency) external {
        bytes32 slotC = SYNCED_CURRENCY_SLOT;
        bytes32 slotR = SYNCED_RESERVES_SLOT;
        uint256 cur = uint256(uint160(Currency.unwrap(currency)));
        assembly ("memory-safe") {
            tstore(slotC, cur)
        }
        if (currency.isAddressZero()) {
            assembly ("memory-safe") {
                tstore(slotR, 0)
            }
        } else {
            uint256 bal = currency.balanceOfSelf();
            assembly ("memory-safe") {
                tstore(slotR, bal)
            }
        }
    }

    /// @inheritdoc IPoolManager
    function settle() external payable onlyWhenUnlocked returns (uint256 paid) {
        Currency currency = _getSyncedCurrency();
        if (currency.isAddressZero()) {
            paid = msg.value;
            _resetSynced();
        } else {
            if (msg.value > 0) revert NonzeroNativeValue();
            bytes32 slotR = SYNCED_RESERVES_SLOT;
            uint256 reservesBefore;
            assembly ("memory-safe") {
                reservesBefore := tload(slotR)
            }
            paid = currency.balanceOfSelf() - reservesBefore;
            _resetSynced();
        }
        _accountDelta(currency, paid.toInt128(), msg.sender);
    }

    /// @inheritdoc IPoolManager
    function take(Currency currency, address to, uint256 amount) external onlyWhenUnlocked {
        unchecked {
            _accountDelta(currency, -int128(int256(amount)), msg.sender);
            currency.transfer(to, amount);
        }
    }

    function _getSyncedCurrency() internal view returns (Currency currency) {
        bytes32 slotC = SYNCED_CURRENCY_SLOT;
        uint256 v;
        assembly ("memory-safe") {
            v := tload(slotC)
        }
        currency = Currency.wrap(address(uint160(v)));
    }

    function _resetSynced() internal {
        bytes32 slotC = SYNCED_CURRENCY_SLOT;
        bytes32 slotR = SYNCED_RESERVES_SLOT;
        assembly ("memory-safe") {
            tstore(slotC, 0)
            tstore(slotR, 0)
        }
    }

    /// @notice Returns pool state: initialized flag, sqrt price, and tick from slot0
    function getPoolState(PoolId id) external view returns (bool initialized, uint160 sqrtPriceX96, int24 tick) {
        PoolState storage state = _getPool(id);
        sqrtPriceX96 = state.slot0.sqrtPriceX96();
        initialized = sqrtPriceX96 != 0;
        tick = state.slot0.tick();
    }

    /// @notice Returns the pool state storage for a given pool id (for internal use / protocol fees pattern)
    function _getPool(PoolId id) internal view returns (PoolState storage) {
        return _pools[id];
    }

    /// @inheritdoc IPoolManager
    function currencyDelta(address target, Currency currency) external view override returns (int256) {
        return CurrencyDelta.getDelta(currency, target);
    }
}
