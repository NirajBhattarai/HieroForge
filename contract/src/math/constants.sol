// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/// @dev The minimum tick spacing value drawn from the range of type int16 that is greater than 0, i.e. min from the range [1, 32767]
int24 constant MIN_TICK_SPACING = 1;
/// @dev The maximum tick spacing value drawn from the range of type int16, i.e. max from the range [1, 32767]
int24 constant MAX_TICK_SPACING = type(int16).max;
