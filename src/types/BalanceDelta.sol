// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/// @dev Two `int128` values packed into a single `int256` where the upper 128 bits represent the amount0
/// and the lower 128 bits represent the amount1.
type BalanceDelta is int256;

using {amount0, amount1} for BalanceDelta global;

function amount0(BalanceDelta delta) pure returns (int128) {
    return int128(int256(BalanceDelta.unwrap(delta)) >> 128);
}

function amount1(BalanceDelta delta) pure returns (int128) {
    return int128(BalanceDelta.unwrap(delta));
}
