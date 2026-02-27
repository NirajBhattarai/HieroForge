// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {PoolId} from "./types/PoolId.sol";
import {Currency} from "./types/Currency.sol";
import {PoolState} from "./types/PoolState.sol";
import {initialPoolState} from "./types/Slot0.sol";
import {ModifyLiquidityParams} from "./types/ModifyLiquidityParams.sol";
import {SwapParams} from "./types/SwapParams.sol";
import {SwapResult} from "./types/SwapResult.sol";
import {BalanceDelta, toBalanceDelta} from "./types/BalanceDelta.sol";

/// @title PoolManager
/// @notice Holds pool state and implements initialize and swap (Uniswap v4-style)
contract PoolManager is IPoolManager {
    mapping(PoolId id => PoolState) internal _pools;

    /// @inheritdoc IPoolManager
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external override returns (int24 tick) {
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
        returns (BalanceDelta callerDelta, BalanceDelta feesAccrued)
    {
        key.validate();
        PoolId id = key.toId();
        PoolState storage state = _getPool(id);

        BalanceDelta principalDelta;
        state.checkPoolInitialized();
        (principalDelta, feesAccrued) = state.doModifyLiquidity(params, hookData);

        // fee delta and principal delta are both accrued to the caller
        callerDelta = toBalanceDelta(
            principalDelta.amount0() + feesAccrued.amount0(), principalDelta.amount1() + feesAccrued.amount1()
        );
        emit ModifyLiquidity(
            id,
            msg.sender,
            params.owner,
            params.tickLower,
            params.tickUpper,
            params.liquidityDelta,
            callerDelta.amount0(),
            callerDelta.amount1()
        );
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
        returns (BalanceDelta swapDelta)
    {
        if (params.amountSpecified == 0) revert IPoolManager.SwapAmountCannotBeZero();
        key.validate();
        PoolId id = key.toId();
        PoolState storage state = _getPool(id);
        state.checkPoolInitialized();

        Currency inputCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        swapDelta = _swap(state, id, params, inputCurrency);
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
}
