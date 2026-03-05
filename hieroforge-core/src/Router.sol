// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {IUnlockCallback} from "./callback/IUnlockCallback.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {ModifyLiquidityParams} from "./types/ModifyLiquidityParams.sol";
import {SwapParams} from "./types/SwapParams.sol";
import {BalanceDelta} from "./types/BalanceDelta.sol";
import {Currency} from "./types/Currency.sol";
import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";

/// @notice Router that calls modifyLiquidity or swap from within the unlock callback (Uniswap v4-style).
/// Implements settlement and transfer: settle negative deltas, take positive deltas.
contract Router is IUnlockCallback {
    IPoolManager public immutable manager;

    uint8 internal constant ACTION_MODIFY_LIQUIDITY = 0;
    uint8 internal constant ACTION_SWAP = 1;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    /// @notice Modify liquidity via unlock callback; caller pays or receives tokens per delta.
    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes memory hookData)
        external
        payable
        returns (BalanceDelta callerDelta, BalanceDelta feesAccrued)
    {
        return abi.decode(
            manager.unlock(
                abi.encode(ACTION_MODIFY_LIQUIDITY, msg.sender, key, abi.encode(params, hookData))
            ),
            (BalanceDelta, BalanceDelta)
        );
    }

    /// @notice Execute swap via unlock callback; caller receives output, router pays input from its balance.
    function swap(PoolKey memory key, SwapParams memory params, bytes memory hookData)
        external
        payable
        returns (BalanceDelta swapDelta)
    {
        swapDelta = abi.decode(
            manager.unlock(abi.encode(ACTION_SWAP, msg.sender, key, abi.encode(params, hookData))),
            (BalanceDelta)
        );
    }

    function unlockCallback(bytes calldata rawData) external override returns (bytes memory) {
        require(msg.sender == address(manager), "Router: only manager");
        (uint8 action, address sender, PoolKey memory key, bytes memory payload) =
            abi.decode(rawData, (uint8, address, PoolKey, bytes));

        if (action == ACTION_MODIFY_LIQUIDITY) {
            (ModifyLiquidityParams memory params, bytes memory hookData) =
                abi.decode(payload, (ModifyLiquidityParams, bytes));
            (BalanceDelta callerDelta, BalanceDelta feesAccrued) =
                manager.modifyLiquidity(key, params, hookData);
            _settleAndTake(key, sender, callerDelta.amount0(), callerDelta.amount1());
            return abi.encode(callerDelta, feesAccrued);
        } else {
            assert(action == ACTION_SWAP);
            (SwapParams memory params, bytes memory hookData) = abi.decode(payload, (SwapParams, bytes));
            BalanceDelta delta = manager.swap(key, params, hookData);
            _settleAndTake(key, sender, delta.amount0(), delta.amount1());
            return abi.encode(delta);
        }
    }

    function _settleAndTake(PoolKey memory key, address sender, int128 delta0, int128 delta1) internal {
        if (delta0 < 0) _settle(key.currency0, uint256(uint128(-delta0)));
        if (delta1 < 0) _settle(key.currency1, uint256(uint128(-delta1)));
        if (delta0 > 0) manager.take(key.currency0, sender, uint256(uint128(delta0)));
        if (delta1 > 0) manager.take(key.currency1, sender, uint256(uint128(delta1)));
    }

    function _settle(Currency currency, uint256 amount) internal {
        if (Currency.unwrap(currency) == address(0)) {
            manager.settle{value: amount}();
            return;
        }
        manager.sync(currency);
        require(
            IERC20Minimal(Currency.unwrap(currency)).transfer(address(manager), amount),
            "Router: transfer failed"
        );
        manager.settle();
    }
}
