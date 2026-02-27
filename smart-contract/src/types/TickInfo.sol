// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @notice Info stored for each initialized tick (Uniswap v4-style)
struct TickInfo {
    uint128 liquidityGross;
    int128 liquidityNet;
    uint256 feeGrowthOutside0X128;
    uint256 feeGrowthOutside1X128;
}
