// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @notice Parameters for modifyLiquidity (Uniswap v4-style)
struct ModifyLiquidityParams {
    // the address that owns the position
    address owner;
    // the lower and upper tick of the position
    int24 tickLower;
    int24 tickUpper;
    // any change in liquidity
    int128 liquidityDelta;
    // the spacing between ticks
    int24 tickSpacing;
    // used to distinguish positions of the same owner, at the same tick range
    bytes32 salt;
}
