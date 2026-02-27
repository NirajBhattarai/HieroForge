// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @notice Two int128 values packed in one int256: upper 128 = amount0, lower 128 = amount1 (Uniswap v4-style)
type BalanceDelta is int256;

using BalanceDeltaLibrary for BalanceDelta global;

/// @notice Build a BalanceDelta from amount0 and amount1
function toBalanceDelta(int128 amount0, int128 amount1) pure returns (BalanceDelta) {
    int256 packed;
    assembly ("memory-safe") {
        packed := or(shl(128, amount0), and(sub(shl(128, 1), 1), amount1))
    }
    return BalanceDelta.wrap(packed);
}

library BalanceDeltaLibrary {
    BalanceDelta internal constant ZERO_DELTA = BalanceDelta.wrap(0);

    function amount0(BalanceDelta d) internal pure returns (int128 _amount0) {
        assembly ("memory-safe") {
            _amount0 := sar(128, d)
        }
    }

    function amount1(BalanceDelta d) internal pure returns (int128 _amount1) {
        assembly ("memory-safe") {
            _amount1 := signextend(15, d)
        }
    }
}
