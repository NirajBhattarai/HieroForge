// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @notice State stored for each position (Uniswap v4 Position.State-style)
struct PositionState {
    uint128 liquidity;
    uint256 feeGrowthInside0LastX128;
    uint256 feeGrowthInside1LastX128;
}
