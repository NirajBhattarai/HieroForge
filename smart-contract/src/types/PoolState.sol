// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Slot0} from "./Slot0.sol";
import {TickInfo} from "./TickInfo.sol";
import {PositionState} from "./PositionState.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";

/// @notice The state of a pool (Uniswap v4-style)
/// @dev feeGrowthGlobal can be artificially inflated; for pools with a single liquidity position,
///      actors can donate to themselves to inflate feeGrowthGlobal atomically with collecting fees.
struct PoolState {
    Slot0 slot0;
    uint256 feeGrowthGlobal0X128;
    uint256 feeGrowthGlobal1X128;
    uint128 liquidity;
    mapping(int24 tick => TickInfo) ticks;
    mapping(int16 wordPos => uint256) tickBitmap;
    mapping(bytes32 positionKey => PositionState) positions;
}

/// @notice Reverts if the given pool has not been initialized (Uniswap v4-style)
/// @param self The pool state storage
function checkPoolInitialized(PoolState storage self) view {
    if (self.slot0.sqrtPriceX96() == 0) revert IPoolManager.PoolNotInitialized();
}
