// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @notice Parameters for modifyLiquidity (taken as argument by modifyLiquidity)
struct ModifyLiquidityParams {
    // the lower and upper tick of the position
    int24 tickLower;
    int24 tickUpper;
    // how to modify the liquidity
    int256 liquidityDelta;
    // a value to set if you want unique liquidity positions at the same range
    bytes32 salt;
}
