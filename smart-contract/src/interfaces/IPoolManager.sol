// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {PoolKey} from "../types/PoolKey.sol";
import {PoolId} from "../types/PoolId.sol";
import {Currency} from "../types/Currency.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "../types/ModifyLiquidityParams.sol";
import {SwapParams} from "../types/SwapParams.sol";

/// @title IPoolManager
/// @notice Minimal interface for pool operations (Uniswap v4-style)
interface IPoolManager {
    /// @notice Thrown when initializing an already initialized pool
    error PoolAlreadyInitialized();
    /// @notice Thrown when interacting with a pool that is not initialized
    error PoolNotInitialized();
    /// @notice Thrown when swap is called with amountSpecified == 0
    error SwapAmountCannotBeZero();

    /// @notice Emitted when a new pool is initialized (Uniswap v4-style)
    /// @param id The abi encoded hash of the pool key struct for the new pool
    /// @param currency0 The first currency of the pool by address sort order
    /// @param currency1 The second currency of the pool by address sort order
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param tickSpacing The minimum number of ticks between initialized ticks
    /// @param hooks The hooks contract address for the pool, or address(0) if none
    /// @param sqrtPriceX96 The price of the pool on initialization
    /// @param tick The initial tick of the pool corresponding to the initialized price
    event Initialize(
        PoolId indexed id,
        Currency indexed currency0,
        Currency indexed currency1,
        uint24 fee,
        int24 tickSpacing,
        address hooks,
        uint160 sqrtPriceX96,
        int24 tick
    );

    /// @notice Emitted when liquidity is modified in a pool
    /// @param id The pool id
    /// @param sender The address that called modifyLiquidity
    /// @param owner The owner of the position (from params)
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param liquidityDelta The change in liquidity (L)
    /// @param amount0 The balance delta for currency0 (caller)
    /// @param amount1 The balance delta for currency1 (caller)
    event ModifyLiquidity(
        PoolId indexed id,
        address indexed sender,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        int128 amount0,
        int128 amount1
    );

    /// @notice Emitted for swaps between currency0 and currency1 (Uniswap v4-style)
    /// @param id The pool id
    /// @param sender The address that initiated the swap
    /// @param amount0 The delta of the currency0 balance of the pool
    /// @param amount1 The delta of the currency1 balance of the pool
    /// @param sqrtPriceX96 The sqrt(price) of the pool after the swap (Q64.96)
    /// @param liquidity The liquidity of the pool after the swap
    /// @param tick The tick after the swap
    /// @param fee The swap fee in hundredths of a bip
    event Swap(
        PoolId indexed id,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    /// @notice Initialize a pool with an initial sqrt price
    /// @param key Pool key identifying the pool
    /// @param sqrtPriceX96 Initial sqrt price (Q64.96)
    /// @return tick The initial tick after initialization
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);

    /// @notice Modify liquidity in the given pool
    /// @param key The pool key
    /// @param params tickLower, tickUpper, liquidityDelta, salt
    /// @param hookData Data passed to hooks (if any)
    /// @return callerDelta Balance delta for the caller (principal + fees)
    /// @return feesAccrued Fee delta in the liquidity range (informational)
    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta callerDelta, BalanceDelta feesAccrued);

    /// @notice Swap against the given pool (Uniswap v4-style)
    /// @param key The pool to swap in
    /// @param params zeroForOne, amountSpecified (exact-in if negative, exact-out if positive), sqrtPriceLimitX96
    /// @param hookData Data passed to swap hooks (if any)
    /// @return swapDelta The balance delta of the address swapping (amount0, amount1)
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta swapDelta);
}
