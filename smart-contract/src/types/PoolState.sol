// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Slot0} from "./Slot0.sol";
import {TickInfo} from "./TickInfo.sol";
import {PositionState} from "./PositionState.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta, toBalanceDelta} from "./BalanceDelta.sol";
import {ModifyLiquidityParams} from "./ModifyLiquidityParams.sol";
import {LiquidityMath} from "../libraries/LiquidityMath.sol";
import {MIN_TICK, MAX_TICK} from "../constants.sol";
import {CustomRevert} from "../libraries/CustomRevert.sol";

using CustomRevert for bytes4;

/// @notice Thrown when liquidity at a tick would exceed the maximum allowed per tick
error TickLiquidityOverflow(int24 tick);

/// @notice Thrown when the tick is not enumerated by the tick spacing (tick % tickSpacing != 0)
error TickMisaligned(int24 tick, int24 tickSpacing);

struct ModifyLiquidityState {
    bool flippedLower;
    uint128 liquidityGrossAfterLower;
    bool flippedUpper;
    uint128 liquidityGrossAfterUpper;
}

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

/// @notice Updates a tick and returns true if the tick was flipped from initialized to uninitialized, or vice versa
/// @param self The mapping containing all tick information for initialized ticks
/// @param tick The tick that will be updated
/// @param liquidityDelta A new amount of liquidity to be added (subtracted) when tick is crossed from left to right (right to left)
/// @param upper true for updating a position's upper tick, or false for updating a position's lower tick
/// @return flipped Whether the tick was flipped from initialized to uninitialized, or vice versa
/// @return liquidityGrossAfter The total amount of liquidity for all positions that references the tick after the update
function updateTick(PoolState storage self, int24 tick, int128 liquidityDelta, bool upper)
    returns (bool flipped, uint128 liquidityGrossAfter)
{
    TickInfo storage info = self.ticks[tick];

    uint128 liquidityGrossBefore = info.liquidityGross;
    int128 liquidityNetBefore = info.liquidityNet;

    liquidityGrossAfter = LiquidityMath.addDelta(liquidityGrossBefore, liquidityDelta);

    flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

    if (liquidityGrossBefore == 0) {
        // by convention, we assume that all growth before a tick was initialized happened _below_ the tick
        if (tick <= self.slot0.tick()) {
            info.feeGrowthOutside0X128 = self.feeGrowthGlobal0X128;
            info.feeGrowthOutside1X128 = self.feeGrowthGlobal1X128;
        }
    }

    // when the lower (upper) tick is crossed left to right, liquidity must be added (removed)
    // when the lower (upper) tick is crossed right to left, liquidity must be removed (added)
    int128 liquidityNet = upper ? liquidityNetBefore - liquidityDelta : liquidityNetBefore + liquidityDelta;
    assembly ("memory-safe") {
        // liquidityGrossAfter and liquidityNet are packed in the first slot of `info`
        // So we can store them with a single sstore by packing them ourselves first
        sstore(
            info.slot,
            // bitwise OR to pack liquidityGrossAfter and liquidityNet
            or(
                // Put liquidityGrossAfter in the lower bits, clearing out the upper bits
                and(liquidityGrossAfter, 0xffffffffffffffffffffffffffffffff),
                // Shift liquidityNet to put it in the upper bits (no need for signextend since we're shifting left)
                shl(128, liquidityNet)
            )
        )
    }
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
    {
        ModifyLiquidityState memory state;

        // if we need to update the ticks, do it
        if (liquidityDelta != 0) {
            (state.flippedLower, state.liquidityGrossAfterLower) = updateTick(self, tickLower, liquidityDelta, false);
            (state.flippedUpper, state.liquidityGrossAfterUpper) = updateTick(self, tickUpper, liquidityDelta, true);

            // `>` and `>=` are logically equivalent here but `>=` is cheaper
            if (liquidityDelta >= 0) {
                uint128 maxLiquidityPerTick = tickSpacingToMaxLiquidityPerTick(params.tickSpacing);
                if (state.liquidityGrossAfterLower > maxLiquidityPerTick) {
                    TickLiquidityOverflow.selector.revertWith(tickLower);
                }
                if (state.liquidityGrossAfterUpper > maxLiquidityPerTick) {
                    TickLiquidityOverflow.selector.revertWith(tickUpper);
                }
            }

            if (state.flippedLower) {
                flipTick(self.tickBitmap, tickLower, params.tickSpacing);
            }
            if (state.flippedUpper) {
                flipTick(self.tickBitmap, tickUpper, params.tickSpacing);
            }
        }
    }
}

/// @notice Derives max liquidity per tick from given tick spacing
/// @dev Executed when adding liquidity
/// @param tickSpacing The amount of required tick separation, realized in multiples of `tickSpacing`
///     e.g., a tickSpacing of 3 requires ticks to be initialized every 3rd tick i.e., ..., -6, -3, 0, 3, 6, ...
/// @return result The max liquidity per tick
function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) pure returns (uint128 result) {
    // Equivalent to:
    // int24 minTick = (MIN_TICK / tickSpacing); if (MIN_TICK % tickSpacing != 0) minTick--;
    // int24 maxTick = (MAX_TICK / tickSpacing); uint24 numTicks = maxTick - minTick + 1;
    // return type(uint128).max / numTicks; (bounds match constants.MIN_TICK / MAX_TICK)
    // tick spacing will never be 0 since constants.MIN_TICK_SPACING is 1
    assembly ("memory-safe") {
        tickSpacing := signextend(2, tickSpacing)
        let minTick := sub(sdiv(MIN_TICK, tickSpacing), slt(smod(MIN_TICK, tickSpacing), 0))
        let maxTick := sdiv(MAX_TICK, tickSpacing)
        let numTicks := add(sub(maxTick, minTick), 1)
        result := div(sub(shl(128, 1), 1), numTicks)
    }
}

/// @notice Flips the initialized state for a given tick from false to true, or vice versa (Uniswap v4-style)
/// @dev Equivalent to TickBitmap.flipTick in v4-core; tick must be a multiple of tickSpacing
/// @param self The mapping storing packed tick-initialized bits (wordPos => word)
/// @param tick The tick to flip (must satisfy tick % tickSpacing == 0)
/// @param tickSpacing The spacing between usable ticks
function flipTick(mapping(int16 wordPos => uint256) storage self, int24 tick, int24 tickSpacing) {
    assembly ("memory-safe") {
        tick := signextend(2, tick)
        tickSpacing := signextend(2, tickSpacing)
        // if (tick % tickSpacing != 0) revert TickMisaligned(tick, tickSpacing);
        if smod(tick, tickSpacing) {
            let fmp := mload(0x40)
            mstore(fmp, 0xd4d8f3e6) // selector for TickMisaligned(int24,int24)
            mstore(add(fmp, 0x20), tick)
            mstore(add(fmp, 0x40), tickSpacing)
            revert(add(fmp, 0x1c), 0x44)
        }
        // compressed = tick / tickSpacing (tick already aligned)
        tick := sdiv(tick, tickSpacing)
        // wordPos = compressed >> 8, bitPos = compressed & 0xff
        mstore(0, sar(8, tick))
        mstore(0x20, self.slot)
        let slot := keccak256(0, 0x40)
        // self[wordPos] ^= (1 << bitPos)
        sstore(slot, xor(sload(slot), shl(and(tick, 0xff), 1)))
    }
}
