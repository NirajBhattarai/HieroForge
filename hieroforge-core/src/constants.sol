// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

// Protocol constants (Uniswap v4-style values)
// See: Uniswap v4-core/src/libraries/TickMath.sol

/// @dev Minimum tick that may be passed to getSqrtPriceAtTick (log base 1.0001 of 2**-128)
int24 constant MIN_TICK = -887272;

/// @dev Maximum tick that may be passed to getSqrtPriceAtTick (log base 1.0001 of 2**128)
int24 constant MAX_TICK = 887272;

/// @dev Minimum tick spacing; ticks that involve positions must be a multiple of tick spacing
/// @dev Uniswap v4: range [1, 32767]
int24 constant MIN_TICK_SPACING = 1;

/// @dev Maximum tick spacing (type(int16).max)
int24 constant MAX_TICK_SPACING = type(int16).max;
