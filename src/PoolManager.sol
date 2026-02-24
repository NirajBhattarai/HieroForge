// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {PoolId} from "./types/PoolKey.sol";
import {Currency} from "./types/Currency.sol";
import {MIN_TICK_SPACING, MAX_TICK_SPACING} from "./math/constants.sol";
import {PoolState, SwapResult, swap as poolSwap} from "./types/PoolState.sol";
import {BalanceDelta, toBalanceDelta} from "./types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "./types/PoolOperation.sol";
import {CustomRevert} from "./libraries/CustomRevert.sol";

contract PoolManager is IPoolManager {
    using CustomRevert for bytes4;

    mapping(PoolId id => PoolState) internal _pools;

    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick) {
        // TODO: revert with low level function to save gas
        if (key.tickSpacing < MIN_TICK_SPACING) revert TickSpacingTooSmall(key.tickSpacing);
        if (key.tickSpacing > MAX_TICK_SPACING) revert TickSpacingTooLarge(key.tickSpacing);

        if (Currency.unwrap(key.token0) >= Currency.unwrap(key.token1)) {
            revert CurrenciesOutOfOrderOrEqual(Currency.unwrap(key.token0), Currency.unwrap(key.token1));
        }

        // TODO: Fee We will get
        // uint24 lpFee = key.fee.getInitialLPFee();

        // NOTE: Hooks are not yet wired into the pool. Current flow is create-pool → swap only.
        // Hooks will be added once this minimal path is in place.

        PoolId id = key.toId();
        tick = _pools[id].initialize(sqrtPriceX96, 0);

        emit Initialize(id, key.token0, key.token1, 0, key.tickSpacing, key.hooks, sqrtPriceX96, tick);
    }

    /// @inheritdoc IPoolManager
    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta callerDelta, BalanceDelta feesAccrued)
    {
        PoolId id = key.toId();

        {
            PoolState storage poolState = _getPool(id);
            poolState.checkPoolInitialized();

            BalanceDelta principalDelta;
            (principalDelta, feesAccrued) = poolState.modifyLiquidity(params, hookData);

            callerDelta = principalDelta + feesAccrued;
        }

        // event is emitted before the afterModifyLiquidity call to ensure events are always emitted in order
        emit ModifyLiquidity(id, msg.sender, params.tickLower, params.tickUpper, params.liquidityDelta, params.salt);
        _accountPoolBalanceDelta(key, callerDelta, msg.sender);
    }

    /// @notice Accounts the deltas of 2 currencies to a target address
    function _accountPoolBalanceDelta(PoolKey memory key, BalanceDelta delta, address target) internal {
        _accountDelta(key.token0, delta.amount0(), target);
        _accountDelta(key.token1, delta.amount1(), target);
    }

    /// @notice Adds a balance delta in a currency for a target address
    function _accountDelta(Currency currency, int128 delta, address target) internal {
        if (delta == 0) return;

        (int256 previous, int256 next) = currency.applyDelta(target, delta);

        // if (next == 0) {
        //     NonzeroDeltaCount.decrement();
        // } else if (previous == 0) {
        //     NonzeroDeltaCount.increment();
        // }
    }

    function _swap(PoolState storage pool, PoolId id, SwapParams memory params, Currency inputCurrency)
        internal
        returns (BalanceDelta callerDelta, BalanceDelta feesAccrued)
    {
        (BalanceDelta delta, uint256 amountToProtocol, uint24 swapFee, SwapResult memory swapResult) =
            poolSwap(pool, params);
        callerDelta = delta;
        feesAccrued = toBalanceDelta(0, 0); // TODO: derive from amountToProtocol/swapFee when fee accounting is wired
    }

    /// @inheritdoc IPoolManager
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta callerDelta, BalanceDelta feesAccrued)
    {
        if (params.amountSpecified == 0) SwapAmountCannotBeZero.selector.revertWith();
        PoolId id = key.toId();

        PoolState storage pool = _getPool(id);
        pool.checkPoolInitialized();

        (callerDelta, feesAccrued) = _swap(pool, id, params, params.zeroForOne ? key.token0 : key.token1);
    }

    /// @notice Implementation of the _getPool function defined in ProtocolFees
    function _getPool(PoolId id) internal view returns (PoolState storage) {
        return _pools[id];
    }
}
