// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Currency} from "./Currency.sol";
import {PoolIdLibrary} from "./PoolId.sol";
import {MIN_TICK_SPACING, MAX_TICK_SPACING} from "../constants.sol";

using PoolIdLibrary for PoolKey global;

/// @notice Key for identifying a pool (Uniswap v4-style)
struct PoolKey {
    /// @notice The lower currency of the pool, sorted numerically
    Currency currency0;
    /// @notice The higher currency of the pool, sorted numerically
    Currency currency1;
    /// @notice The pool LP fee, capped at 1_000_000
    uint24 fee;
    /// @notice Ticks that involve positions must be a multiple of tick spacing
    int24 tickSpacing;
    /// @notice The hooks contract (address(0) for no hooks)
    address hooks;
}

/// @notice Thrown when currencies are not properly sorted (currency0 >= currency1)
error TokensMustBeSorted();

/// @notice Thrown when tickSpacing is not in [MIN_TICK_SPACING, MAX_TICK_SPACING]
error InvalidTickSpacing();

/// @notice Validates that a pool key is valid
function validate(PoolKey memory key) pure {
    if (Currency.unwrap(key.currency0) >= Currency.unwrap(key.currency1)) revert TokensMustBeSorted();
    if (key.tickSpacing < MIN_TICK_SPACING || key.tickSpacing > MAX_TICK_SPACING) revert InvalidTickSpacing();
}

using {validate} for PoolKey global;
