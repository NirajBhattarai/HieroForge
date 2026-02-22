// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

struct ModifyLiquidityState {
    bool flippedLower;
    uint128 liquidityGrossAfterLower;
    bool flippedUpper;
    uint128 liquidityGrossAfterUpper;
}
