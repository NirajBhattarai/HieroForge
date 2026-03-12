// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
import {BalanceDelta} from "hieroforge-core/types/BalanceDelta.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {Currency} from "hieroforge-core/types/Currency.sol";
import {SwapParams} from "hieroforge-core/types/SwapParams.sol";
import {TickMath} from "hieroforge-core/libraries/TickMath.sol";
import {SafeCast} from "hieroforge-core/libraries/SafeCast.sol";
import {IERC20Minimal} from "hieroforge-core/interfaces/IERC20Minimal.sol";

import {CalldataDecoder} from "./libraries/CalldataDecoder.sol";
import {IV4Router} from "./interfaces/IV4Router.sol";
import {BaseActionsRouter} from "./base/BaseActionsRouter.sol";
import {DeltaResolver} from "./base/DeltaResolver.sol";
import {Actions} from "./libraries/Actions.sol";
import {ActionConstants} from "./libraries/ActionConstants.sol";

/// @title V4Router
/// @notice Router for swapping tokens via hieroforge-core PoolManager (action-based unlock flow)
/// @dev Entry point is _executeActions; inheriting contract (e.g. UniversalRouter) calls _executeV4Swap with (actions, params) encoding
abstract contract V4Router is IV4Router, BaseActionsRouter, DeltaResolver {
    using CalldataDecoder for bytes;
    using SafeCast for uint256;
    using SafeCast for int128;

    constructor(IPoolManager _poolManager) BaseActionsRouter(_poolManager) {}

    /// @inheritdoc BaseActionsRouter
    function _handleAction(uint256 action, bytes calldata params) internal override {
        if (action < Actions.SETTLE) {
            if (action == Actions.SWAP_EXACT_IN_SINGLE) {
                IV4Router.ExactInputSingleParams calldata swapParams = params.decodeSwapExactInSingleParams();
                _swapExactInputSingle(swapParams);
                return;
            } else if (action == Actions.SWAP_EXACT_OUT_SINGLE) {
                IV4Router.ExactOutputSingleParams calldata swapParams = params.decodeSwapExactOutSingleParams();
                _swapExactOutputSingle(swapParams);
                return;
            }
        } else {
            if (action == Actions.SETTLE_ALL) {
                (Currency currency, uint256 maxAmount) = params.decodeCurrencyAndUint256();
                uint256 amount = _getFullDebt(currency);
                if (amount > maxAmount) revert V4TooMuchRequested(maxAmount, amount);
                _settle(currency, msgSender(), amount);
                return;
            } else if (action == Actions.TAKE_ALL) {
                (Currency currency, uint256 minAmount) = params.decodeCurrencyAndUint256();
                uint256 amount = _getFullCredit(currency);
                if (amount < minAmount) revert V4TooLittleReceived(minAmount, amount);
                _take(currency, msgSender(), amount);
                return;
            }
        }
        revert UnsupportedAction(action);
    }

    /// @inheritdoc DeltaResolver
    function _pay(Currency token, address payer, uint256 amount) internal override {
        require(
            IERC20Minimal(Currency.unwrap(token)).transferFrom(payer, address(poolManager), amount),
            "V4Router: transfer failed"
        );
    }

    function _swapExactInputSingle(IV4Router.ExactInputSingleParams calldata params) private {
        uint128 amountIn = params.amountIn;
        if (amountIn == ActionConstants.OPEN_DELTA) {
            amountIn =
                _getFullCredit(params.zeroForOne ? params.poolKey.currency0 : params.poolKey.currency1).toUint128();
        }
        uint128 amountOut =
            _swap(params.poolKey, params.zeroForOne, -int256(uint256(amountIn)), params.hookData).toUint128();
        if (amountOut < params.amountOutMinimum) revert V4TooLittleReceived(params.amountOutMinimum, amountOut);
    }

    function _swapExactOutputSingle(IV4Router.ExactOutputSingleParams calldata params) private {
        uint128 amountOut = params.amountOut;
        if (amountOut == ActionConstants.OPEN_DELTA) {
            amountOut =
                _getFullDebt(params.zeroForOne ? params.poolKey.currency1 : params.poolKey.currency0).toUint128();
        }
        uint128 amountIn = (uint256(
                -int256(_swap(params.poolKey, params.zeroForOne, int256(uint256(amountOut)), params.hookData))
            ))
        .toUint128();
        if (amountIn > params.amountInMaximum) revert V4TooMuchRequested(params.amountInMaximum, amountIn);
    }

    function _swap(PoolKey memory poolKey, bool zeroForOne, int256 amountSpecified, bytes calldata hookData)
        private
        returns (int128 reciprocalAmount)
    {
        uint160 sqrtPriceLimit = zeroForOne ? TickMath.minSqrtPrice() + 1 : TickMath.maxSqrtPrice() - 1;
        BalanceDelta delta = poolManager.swap(
            poolKey,
            SwapParams({
                amountSpecified: amountSpecified,
                tickSpacing: poolKey.tickSpacing,
                zeroForOne: zeroForOne,
                sqrtPriceLimitX96: sqrtPriceLimit,
                lpFeeOverride: 0
            }),
            hookData
        );
        reciprocalAmount = (zeroForOne == (amountSpecified < 0)) ? delta.amount1() : delta.amount0();
    }

    /// @notice Runs the v4 swap payload: decode (actions, params) and execute via unlock
    function _executeV4Swap(bytes calldata input) internal virtual {
        _executeActions(input);
    }
}
