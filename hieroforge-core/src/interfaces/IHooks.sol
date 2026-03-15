// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {BeforeSwapDelta} from "../types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams} from "../types/ModifyLiquidityParams.sol";
import {SwapParams} from "../types/SwapParams.sol";

/// @title IHooks
/// @notice Interface for hook contracts that can be attached to pools.
/// @dev Adapted for Hedera — no EIP-712 permit support. Hook address encodes permissions
///      via its lower 6 bits (see Hooks library). Only implement callbacks your hook needs.
interface IHooks {
    /// @notice Called before a pool is initialized
    /// @param sender The address that called PoolManager.initialize
    /// @param key The pool key being initialized
    /// @param sqrtPriceX96 The initial sqrt price
    /// @param hookData Arbitrary data passed by the caller
    /// @return bytes4 IHooks.beforeInitialize.selector on success
    function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, bytes calldata hookData)
        external
        returns (bytes4);

    /// @notice Called after a pool is initialized
    /// @param sender The address that called PoolManager.initialize
    /// @param key The pool key that was initialized
    /// @param sqrtPriceX96 The initial sqrt price
    /// @param tick The initial tick
    /// @param hookData Arbitrary data passed by the caller
    /// @return bytes4 IHooks.afterInitialize.selector on success
    function afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick,
        bytes calldata hookData
    ) external returns (bytes4);

    /// @notice Called before liquidity is modified
    /// @param sender The address that called PoolManager.modifyLiquidity
    /// @param key The pool key
    /// @param params The modify liquidity parameters
    /// @param hookData Arbitrary data passed by the caller
    /// @return bytes4 IHooks.beforeModifyLiquidity.selector on success
    function beforeModifyLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4);

    /// @notice Called after liquidity is modified
    /// @param sender The address that called PoolManager.modifyLiquidity
    /// @param key The pool key
    /// @param params The modify liquidity parameters
    /// @param delta The balance delta resulting from the modification
    /// @param feesAccrued The fees accrued
    /// @param hookData Arbitrary data passed by the caller
    /// @return bytes4 IHooks.afterModifyLiquidity.selector on success
    function afterModifyLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) external returns (bytes4);

    /// @notice Called before a swap is executed
    /// @param sender The address that called PoolManager.swap
    /// @param key The pool key
    /// @param params The swap parameters
    /// @param hookData Arbitrary data passed by the caller
    /// @return bytes4 IHooks.beforeSwap.selector on success
    /// @return BeforeSwapDelta Any delta adjustments for the swap (usually ZERO_DELTA)
    /// @return uint24 Optional fee override (0 = use pool fee)
    function beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        returns (bytes4, BeforeSwapDelta, uint24);

    /// @notice Called after a swap is executed
    /// @param sender The address that called PoolManager.swap
    /// @param key The pool key
    /// @param params The swap parameters
    /// @param delta The balance delta from the swap
    /// @param hookData Arbitrary data passed by the caller
    /// @return bytes4 IHooks.afterSwap.selector on success
    /// @return int128 Any unspecified delta adjustment
    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external returns (bytes4, int128);
}
