// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {IUnlockCallback} from "./callback/IUnlockCallback.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {ModifyLiquidityParams} from "./types/ModifyLiquidityParams.sol";
import {BalanceDelta} from "./types/BalanceDelta.sol";
import {Currency} from "./types/Currency.sol";
import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";

/// @notice Router that calls modifyLiquidity from within the unlock callback (Uniswap v4-style).
/// Implements settlement and transfer: settle negative deltas, take positive deltas.
contract ModifyLiquidityRouter is IUnlockCallback {
    IPoolManager public immutable manager;

    struct CallbackData {
        address sender;
        PoolKey key;
        ModifyLiquidityParams params;
        bytes hookData;
    }

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes memory hookData)
        external
        payable
        returns (BalanceDelta callerDelta, BalanceDelta feesAccrued)
    {
        return abi.decode(
            manager.unlock(abi.encode(CallbackData({sender: msg.sender, key: key, params: params, hookData: hookData}))),
            (BalanceDelta, BalanceDelta)
        );
    }

    function unlockCallback(bytes calldata rawData) external override returns (bytes memory) {
        require(msg.sender == address(manager), "only manager");
        CallbackData memory data = abi.decode(rawData, (CallbackData));

        (BalanceDelta callerDelta, BalanceDelta feesAccrued) =
            manager.modifyLiquidity(data.key, data.params, data.hookData);

        int128 delta0 = callerDelta.amount0();
        int128 delta1 = callerDelta.amount1();

        if (delta0 < 0) _settle(data.key.currency0, uint256(uint128(-delta0)));
        if (delta1 < 0) _settle(data.key.currency1, uint256(uint128(-delta1)));
        if (delta0 > 0) manager.take(data.key.currency0, data.sender, uint256(uint128(delta0)));
        if (delta1 > 0) manager.take(data.key.currency1, data.sender, uint256(uint128(delta1)));

        return abi.encode(callerDelta, feesAccrued);
    }

    function _settle(Currency currency, uint256 amount) internal {
        if (Currency.unwrap(currency) == address(0)) {
            manager.settle{value: amount}();
            return;
        }
        manager.sync(currency);
        require(
            IERC20Minimal(Currency.unwrap(currency)).transfer(address(manager), amount),
            "ModifyLiquidityRouter: transfer failed"
        );
        manager.settle();
    }
}
