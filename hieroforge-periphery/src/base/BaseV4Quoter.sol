// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {PoolId} from "hieroforge-core/types/PoolId.sol";
import {SwapParams} from "hieroforge-core/types/SwapParams.sol";
import {BalanceDelta} from "hieroforge-core/types/BalanceDelta.sol";
import {TickMath} from "hieroforge-core/libraries/TickMath.sol";
import {SafeCallback} from "./SafeCallback.sol";
import {QuoterRevert} from "../libraries/QuoterRevert.sol";

/// @title BaseV4Quoter
/// @notice Base for V4Quoter: implements _unlockCallback and _swap for quote simulation (matches Uniswap v4)
abstract contract BaseV4Quoter is SafeCallback {
    using QuoterRevert for *;

    error NotEnoughLiquidity(PoolId poolId);
    error NotSelf();
    error UnexpectedCallSuccess();

    constructor(IPoolManager _poolManager) SafeCallback(_poolManager) {}

    /// @dev Only this address may call this function. Used to mimic internal functions, using an
    /// external call to catch and parse revert reasons
    modifier selfOnly() {
        if (msg.sender != address(this)) revert NotSelf();
        _;
    }

    function _unlockCallback(bytes calldata data) internal override returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).call(data);
        // Every quote path gathers a quote, and then reverts either with QuoteSwap(quoteAmount) or alternative error
        if (success) revert UnexpectedCallSuccess();
        // Bubble the revert string, whether a valid quote or an alternative error
        returnData.bubbleReason();
    }

    /// @dev Execute a swap and return the balance delta
    /// @notice if amountSpecified < 0, the swap is exactInput, otherwise exactOutput
    function _swap(PoolKey memory poolKey, bool zeroForOne, int256 amountSpecified, bytes calldata hookData)
        internal
        returns (BalanceDelta swapDelta)
    {
        uint160 sqrtLimit = zeroForOne ? TickMath.minSqrtPrice() + 1 : TickMath.maxSqrtPrice() - 1;
        swapDelta = poolManager.swap(
            poolKey,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: sqrtLimit,
                tickSpacing: poolKey.tickSpacing,
                lpFeeOverride: 0
            }),
            hookData
        );

        // Check that the pool was not illiquid.
        int128 amountSpecifiedActual = (zeroForOne == (amountSpecified < 0)) ? swapDelta.amount0() : swapDelta.amount1();
        if (int256(amountSpecifiedActual) != amountSpecified) {
            revert NotEnoughLiquidity(poolKey.toId());
        }
    }
}
