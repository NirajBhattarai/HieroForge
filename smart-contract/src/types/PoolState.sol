// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Slot0} from "./Slot0.sol";
import {TickInfo} from "./TickInfo.sol";
import {PositionState} from "./PositionState.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta, toBalanceDelta} from "./BalanceDelta.sol";
import {ModifyLiquidityParams} from "./ModifyLiquidityParams.sol";

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

using {checkPoolInitialized, modifyLiquidity} for PoolState global;

/// @notice Reverts if the given pool has not been initialized (Uniswap v4-style)
/// @param self The pool state storage
function checkPoolInitialized(PoolState storage self) view {
    if (self.slot0.sqrtPriceX96() == 0) revert IPoolManager.PoolNotInitialized();
}

/// @notice Returns the current liquidity in the pool (Uniswap v4-style)
/// @param self The pool state storage
/// @return liquidity The current liquidity (L) in the pool
function getLiquidity(PoolState storage self) view returns (uint128 liquidity) {
    liquidity = self.liquidity;
}

/// @notice Modify liquidity in the pool (Uniswap v4-style). Define only here; implementation is a stub.
/// @param self The pool state storage
/// @param params tickLower, tickUpper, liquidityDelta, salt
/// @param hookData Data passed to hooks (if any)
/// @return callerDelta Balance delta for the caller (principal + fees)
/// @return feesAccrued Fee delta in the liquidity range (informational)
function modifyLiquidity(PoolState storage self, ModifyLiquidityParams memory params, bytes calldata hookData)
    returns (BalanceDelta callerDelta, BalanceDelta feesAccrued)
{
    checkPoolInitialized(self);
    int128 liquidityDelta = params.liquidityDelta;
    int24 tickLower = params.tickLower;
    int24 tickUpper = params.tickUpper;

    // TODO: implement liquidity modification (tick updates, position, fees)
    params;
    hookData;
    callerDelta = toBalanceDelta(0, 0);
    feesAccrued = toBalanceDelta(0, 0);
}
