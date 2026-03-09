// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @notice Full parameter struct for `ModifyLiquidity` pool operations (internal use).
/// @dev Built from ModifyLiquidityParams + owner = msg.sender + tickSpacing from PoolKey.
struct ModifyLiquidityOperation {
    // the address that owns the position (set to msg.sender when building from params)
    address owner;
    // the lower and upper tick of the position
    int24 tickLower;
    int24 tickUpper;
    // any change in liquidity
    int128 liquidityDelta;
    // the spacing between ticks (from PoolKey)
    int24 tickSpacing;
    // used to distinguish positions of the same owner, at the same tick range
    bytes32 salt;
}
