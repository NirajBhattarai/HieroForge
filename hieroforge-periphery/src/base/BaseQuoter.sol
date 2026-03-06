// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {PoolId} from "hieroforge-core/types/PoolId.sol";
import {SwapParams} from "hieroforge-core/types/SwapParams.sol";
import {BalanceDelta} from "hieroforge-core/types/BalanceDelta.sol";
import {IUnlockCallback} from "hieroforge-core/callback/IUnlockCallback.sol";
import {TickMath} from "hieroforge-core/libraries/TickMath.sol";
import {QuoterRevert} from "../libraries/QuoterRevert.sol";

/// @title BaseQuoter
/// @notice Base for Quoter: implements unlockCallback and _swap for quote simulation
abstract contract BaseQuoter is IUnlockCallback {
    using QuoterRevert for *;

    IPoolManager public immutable poolManager;

    error NotPoolManager();
    error NotSelf();
    error UnexpectedCallSuccess();
    error NotEnoughLiquidity(PoolId poolId);

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    modifier selfOnly() {
        if (msg.sender != address(this)) revert NotSelf();
        _;
    }

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).call(data);
        if (success) revert UnexpectedCallSuccess();
        returnData.bubbleReason();
    }

    /// @dev Simulates a swap and returns the balance delta (used inside quote callbacks)
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

        int128 amountSpecifiedActual = (zeroForOne == (amountSpecified < 0)) ? swapDelta.amount0() : swapDelta.amount1();
        if (int256(amountSpecifiedActual) != amountSpecified) {
            revert NotEnoughLiquidity(poolKey.toId());
        }
    }
}
