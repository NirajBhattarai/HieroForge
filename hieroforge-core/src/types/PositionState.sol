// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {FullMath} from "../libraries/FullMath.sol";
import {LiquidityMath} from "../libraries/LiquidityMath.sol";

/// @notice State stored for each position (Uniswap v4 Position.State-style)
struct PositionState {
    uint128 liquidity;
    uint256 feeGrowthInside0LastX128;
    uint256 feeGrowthInside1LastX128;
}

using PositionStateLibrary for PositionState global;

/// @notice Library to update position state and compute fees owed (Uniswap v4-style)
library PositionStateLibrary {
    uint256 private constant Q128 = 1 << 128;

    /// @notice Updates position with new fee growth and liquidity delta; returns fees owed in token0 and token1
    /// @param self The position state storage
    /// @param liquidityDelta Change in position liquidity (signed)
    /// @param feeGrowthInside0X128 Current fee growth inside range for token0 (Q128)
    /// @param feeGrowthInside1X128 Current fee growth inside range for token1 (Q128)
    /// @return feesOwed0 Fees owed in token0 (from fee growth since last update)
    /// @return feesOwed1 Fees owed in token1 (from fee growth since last update)
    function update(
        PositionState storage self,
        int128 liquidityDelta,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) internal returns (uint256 feesOwed0, uint256 feesOwed1) {
        uint128 liquidityBefore = self.liquidity;
        if (liquidityBefore > 0) {
            feesOwed0 = FullMath.mulDiv(feeGrowthInside0X128 - self.feeGrowthInside0LastX128, liquidityBefore, Q128);
            feesOwed1 = FullMath.mulDiv(feeGrowthInside1X128 - self.feeGrowthInside1LastX128, liquidityBefore, Q128);
        }
        self.feeGrowthInside0LastX128 = feeGrowthInside0X128;
        self.feeGrowthInside1LastX128 = feeGrowthInside1X128;
        self.liquidity = LiquidityMath.addDelta(liquidityBefore, liquidityDelta);
    }
}
