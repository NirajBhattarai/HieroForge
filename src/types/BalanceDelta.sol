// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/// @dev Two `int128` values packed into a single `int256` where the upper 128 bits represent the amount0
/// and the lower 128 bits represent the amount1.
type BalanceDelta is int256;

using {amount0, amount1, add as +} for BalanceDelta global;

function toBalanceDelta(int128 _amount0, int128 _amount1) pure returns (BalanceDelta balanceDelta) {
    assembly ("memory-safe") {
        balanceDelta := or(shl(128, _amount0), and(sub(shl(128, 1), 1), _amount1))
    }
}

function add(BalanceDelta a, BalanceDelta b) pure returns (BalanceDelta) {
    return BalanceDelta.wrap(BalanceDelta.unwrap(a) + BalanceDelta.unwrap(b));
}

function amount0(BalanceDelta delta) pure returns (int128) {
    return int128(int256(BalanceDelta.unwrap(delta)) >> 128);
}

function amount1(BalanceDelta delta) pure returns (int128) {
    return int128(BalanceDelta.unwrap(delta));
}
