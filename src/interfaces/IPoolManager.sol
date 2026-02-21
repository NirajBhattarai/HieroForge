// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {PoolId} from "../types/PoolKey.sol";
import {Currency} from "../types/Currency.sol";
import {IHooks} from "./IHooks.sol";
import {PoolKey} from "../types/PoolKey.sol";

interface IPoolManager {
    /// @notice Pools require tickSpacing >= MIN_TICK_SPACING (1) in #initialize to prevent underflow
    error TickSpacingTooSmall(int24 tickSpacing);
    /// @notice Pools are limited to type(int16).max tickSpacing in #initialize, to prevent overflow
    error TickSpacingTooLarge(int24 tickSpacing);
    /// @notice currency0 must be less than currency1 in pool key (strict sort order)
    error CurrenciesOutOfOrderOrEqual(address currency0, address currency1);

    /// @notice Emitted when a new pool is initialized
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
        IHooks hooks,
        uint160 sqrtPriceX96,
        int24 tick
    );

    /// @notice Initialize the state for a given pool ID
    /// @dev A swap fee totaling MAX_SWAP_FEE (100%) makes exact output swaps impossible since the input is entirely consumed by the fee
    /// @param key The pool key for the pool to initialize
    /// @param sqrtPriceX96 The initial square root price
    /// @return tick The initial tick of the pool
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);
}
