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
import {PathKey, PathKeyLibrary} from "./libraries/PathKey.sol";

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
            // ── Swap actions ──
            if (action == Actions.SWAP_EXACT_IN_SINGLE) {
                IV4Router.ExactInputSingleParams calldata swapParams = params.decodeSwapExactInSingleParams();
                _swapExactInputSingle(swapParams);
                return;
            } else if (action == Actions.SWAP_EXACT_IN) {
                IV4Router.ExactInputParams memory swapParams = params.decodeSwapExactInParams();
                _swapExactInput(swapParams);
                return;
            } else if (action == Actions.SWAP_EXACT_OUT_SINGLE) {
                IV4Router.ExactOutputSingleParams calldata swapParams = params.decodeSwapExactOutSingleParams();
                _swapExactOutputSingle(swapParams);
                return;
            } else if (action == Actions.SWAP_EXACT_OUT) {
                IV4Router.ExactOutputParams memory swapParams = params.decodeSwapExactOutParams();
                _swapExactOutput(swapParams);
                return;
            }
        } else {
            // ── Settlement actions ──
            if (action == Actions.SETTLE_ALL) {
                (Currency currency, uint256 maxAmount) = params.decodeCurrencyAndUint256();
                uint256 amount = _getFullDebt(currency);
                if (amount > maxAmount) revert V4TooMuchRequested(maxAmount, amount);
                _settle(currency, msgSender(), amount);
                return;
            } else if (action == Actions.SETTLE) {
                (Currency currency, uint256 amount, bool payerIsUser) = params.decodeCurrencyUint256AndBool();
                amount = _mapSettleAmount(amount, currency);
                _settle(currency, _mapPayer(payerIsUser), amount);
                return;
            } else if (action == Actions.SETTLE_PAIR) {
                (Currency currency0, Currency currency1) = params.decodeCurrencyPair();
                int256 d0 = poolManager.currencyDelta(address(this), currency0);
                int256 d1 = poolManager.currencyDelta(address(this), currency1);
                if (d0 < 0) _settle(currency0, msgSender(), uint256(-d0));
                if (d1 < 0) _settle(currency1, msgSender(), uint256(-d1));
                return;
            } else if (action == Actions.TAKE_ALL) {
                (Currency currency, uint256 minAmount) = params.decodeCurrencyAndUint256();
                uint256 amount = _getFullCredit(currency);
                if (amount < minAmount) revert V4TooLittleReceived(minAmount, amount);
                _take(currency, msgSender(), amount);
                return;
            } else if (action == Actions.TAKE) {
                (Currency currency, address recipient, uint256 amount) = params.decodeCurrencyAddressAndUint256();
                amount = _mapTakeAmount(amount, currency);
                _take(currency, _mapRecipient(recipient), amount);
                return;
            } else if (action == Actions.TAKE_PAIR) {
                (Currency currency0, Currency currency1, address recipient) = params.decodeCurrencyPairAndAddress();
                address to = _mapRecipient(recipient);
                int256 d0 = poolManager.currencyDelta(address(this), currency0);
                int256 d1 = poolManager.currencyDelta(address(this), currency1);
                if (d0 > 0) _take(currency0, to, uint256(d0));
                if (d1 > 0) _take(currency1, to, uint256(d1));
                return;
            } else if (action == Actions.TAKE_PORTION) {
                (Currency currency, address recipient, uint256 bips) = params.decodeCurrencyAddressAndUint256();
                _take(currency, _mapRecipient(recipient), _getFullCredit(currency) * bips / 10_000);
                return;
            } else if (action == Actions.CLOSE_CURRENCY) {
                Currency currency = params.decodeCurrency();
                int256 delta = poolManager.currencyDelta(address(this), currency);
                if (delta < 0) {
                    _settle(currency, msgSender(), uint256(-delta));
                } else if (delta > 0) {
                    _take(currency, msgSender(), uint256(delta));
                }
                return;
            } else if (action == Actions.CLEAR_OR_TAKE) {
                (Currency currency, uint256 amountMax) = params.decodeCurrencyAndUint256();
                uint256 delta = _getFullCredit(currency);
                if (delta > amountMax) {
                    _take(currency, msgSender(), delta);
                }
                // else: credit <= amountMax, leave it (effectively donate dust)
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

    // ─── Single-hop ───────────────────────────────────────────────────────────

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

    // ─── Multi-hop ────────────────────────────────────────────────────────────

    /// @dev Multi-hop exact-input: loop forward through path, each hop's output becomes the next hop's input
    function _swapExactInput(IV4Router.ExactInputParams memory params) private {
        uint128 amountIn = params.amountIn;
        if (amountIn == ActionConstants.OPEN_DELTA) {
            amountIn = _getFullCredit(params.currencyIn).toUint128();
        }

        uint256 pathLength = params.path.length;
        Currency currencyIn = params.currencyIn;

        for (uint256 i = 0; i < pathLength; i++) {
            (PoolKey memory poolKey, bool zeroForOne) =
                PathKeyLibrary.getPoolAndSwapDirectionMemory(params.path[i], currencyIn);
            amountIn = _swapMemory(poolKey, zeroForOne, -int256(uint256(amountIn)), params.path[i].hookData).toUint128();
            currencyIn = params.path[i].intermediateCurrency;
        }
        // After the loop, amountIn holds the final output amount
        if (amountIn < params.amountOutMinimum) revert V4TooLittleReceived(params.amountOutMinimum, amountIn);
    }

    /// @dev Multi-hop exact-output: loop backward through path, each hop's input becomes the next hop's output
    function _swapExactOutput(IV4Router.ExactOutputParams memory params) private {
        uint128 amountOut = params.amountOut;
        if (amountOut == ActionConstants.OPEN_DELTA) {
            amountOut = _getFullDebt(params.currencyOut).toUint128();
        }

        uint256 pathLength = params.path.length;
        Currency currencyOut = params.currencyOut;

        for (uint256 i = pathLength; i > 0; i--) {
            (PoolKey memory poolKey, bool oneForZero) =
                PathKeyLibrary.getPoolAndSwapDirectionMemory(params.path[i - 1], currencyOut);
            // oneForZero means currencyOut is currency0 input side, so we negate to get zeroForOne
            amountOut = (uint256(
                    -int256(_swapMemory(poolKey, !oneForZero, int256(uint256(amountOut)), params.path[i - 1].hookData))
                ))
            .toUint128();
            currencyOut = params.path[i - 1].intermediateCurrency;
        }
        // After the loop, amountOut holds the total input required
        if (amountOut > params.amountInMaximum) revert V4TooMuchRequested(params.amountInMaximum, amountOut);
    }

    // ─── Core swap helpers ────────────────────────────────────────────────────

    /// @dev Single swap against poolManager (calldata hookData — used by single-hop)
    function _swap(PoolKey memory poolKey, bool zeroForOne, int256 amountSpecified, bytes calldata hookData)
        internal
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

    /// @dev Single swap against poolManager (memory hookData — used by multi-hop)
    function _swapMemory(PoolKey memory poolKey, bool zeroForOne, int256 amountSpecified, bytes memory hookData)
        internal
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
