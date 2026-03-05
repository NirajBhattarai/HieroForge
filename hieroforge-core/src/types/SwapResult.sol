// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

// Tracks the state of a pool throughout a swap, and returns these values at the end of the swap
struct SwapResult {
    // the current sqrt(price)
    uint160 sqrtPriceX96;
    // the tick associated with the current price
    int24 tick;
    // the current liquidity in range
    uint128 liquidity;
}
