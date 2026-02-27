// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @notice Parameters for modifyLiquidity (Uniswap v4-style)
struct ModifyLiquidityParams {
    /// @notice The lower tick of the position
    int24 tickLower;
    /// @notice The upper tick of the position
    int24 tickUpper;
    /// @notice Amount of liquidity to add (positive) or remove (negative)
    int256 liquidityDelta;
    /// @notice Salt for unique positions in the same tick range
    bytes32 salt;
}
