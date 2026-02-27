// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {PoolKey} from "../types/PoolKey.sol";
import {PoolId} from "../types/PoolId.sol";
import {Currency} from "../types/Currency.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "../types/ModifyLiquidityParams.sol";

/// @title IPoolManager
/// @notice Minimal interface for pool initialization (Uniswap v4-style)
interface IPoolManager {
    /// @notice Thrown when initializing an already initialized pool
    error PoolAlreadyInitialized();
    /// @notice Thrown when interacting with a pool that is not initialized
    error PoolNotInitialized();

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
}
