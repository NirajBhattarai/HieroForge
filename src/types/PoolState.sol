// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Slot0} from "./Slot0.sol";
import {TickInfo} from "./TickInfo.sol";
import {PositionState} from "./PositionState.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {ModifyLiquidityParams, SwapParams} from "./PoolOperation.sol";
import {BalanceDelta, toBalanceDelta} from "./BalanceDelta.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {ModifyLiquidityState} from "./ModifyLiquidityState.sol";
import {LiquidityMath} from "../math/LiquidityMath.sol";
import {TickBitmap} from "../libraries/TickBitmap.sol";
import {SqrtPriceMath} from "../libraries/SqrtPriceMath.sol";

using {initialize, checkPoolInitialized, modifyLiquidity} for PoolState global;

struct PoolState {
    Slot0 slot0;
    uint128 liquidity;
    mapping(int24 tick => TickInfo) ticks;
    mapping(int16 wordPos => uint256) tickBitmap;
    mapping(bytes32 positionKey => PositionState) positions;
}

struct StepComputations {
    // the price at the beginning of the step
    uint160 sqrtPriceStartX96;
    // the next tick to swap to from the current tick in the swap direction
    int24 tickNext;
    // whether tickNext is initialized or not
    bool initialized;
    // sqrt(price) for the next tick (1/0)
    uint160 sqrtPriceNextX96;
    // how much is being swapped in in this step
    uint256 amountIn;
    // how much is being swapped out
    uint256 amountOut;
}

// Tracks the state of a pool throughout a swap, and returns these values at the end of the swap
struct SwapResult {
    // the current sqrt(price)
    uint160 sqrtPriceX96;
    // the tick associated with the current price
    int24 tick;
    // the current liquidity in range
    uint128 liquidity;
}

/// @dev PoolState contains mappings and can only be used in storage, not memory.
function initialize(PoolState storage self, uint160 sqrtPriceX96, uint24 lpFee) returns (int24 tick) {
    tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
    self.slot0 = Slot0.wrap(bytes32(0)).setSqrtPriceX96(sqrtPriceX96).setTick(tick).setLpFee(lpFee).setProtocolFee(0);
}

/// @notice Reverts if the given pool has not been initialized
function checkPoolInitialized(PoolState storage self) view {
    if (self.slot0.sqrtPriceX96() == 0) revert IPoolManager.PoolNotInitialized();
}

function updateTick(PoolState storage self, int24 tick, int128 liquidityDelta, bool upper)
    returns (bool flipped, uint128 liquidityGrossAfter)
{
    TickInfo storage tickInfo = self.ticks[tick];

    uint128 liquidityGrossBefore = tickInfo.liquidityGross;
    int128 liquidityNetBefore = tickInfo.liquidityNet;

    liquidityGrossAfter = LiquidityMath.addDelta(liquidityGrossBefore, liquidityDelta);

    flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

    if (liquidityGrossBefore == 0) {
        // by convention, we assume that all growth before a tick was initialized happened _below_ the tick
        if (tick <= self.slot0.tick()) {
            // tickInfo.feeGrowthOutside0X128 = self.feeGrowthGlobal0X128;
            // tickInfo.feeGrowthOutside1X128 = self.feeGrowthGlobal1X128;
        }
    }

    // when the lower (upper) tick is crossed left to right, liquidity must be added (removed)
    // when the lower (upper) tick is crossed right to left, liquidity must be removed (added)
    int128 liquidityNet = upper ? liquidityNetBefore - liquidityDelta : liquidityNetBefore + liquidityDelta;

    assembly ("memory-safe") {
        // liquidityGrossAfter and liquidityNet are packed in the first slot of `info`
        // So we can store them with a single sstore by packing them ourselves first
        sstore(
            tickInfo.slot,
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

function modifyLiquidity(PoolState storage self, ModifyLiquidityParams memory params, bytes calldata hookData)
    returns (BalanceDelta delta, BalanceDelta feesAccrued)
{
    int128 liquidityDelta = params.liquidityDelta;
    int24 tickLower = params.tickLower;
    int24 tickUpper = params.tickUpper;
    checkTicks(tickLower, tickUpper);
    {
        ModifyLiquidityState memory state;

        if (liquidityDelta != 0) {
            (state.flippedLower, state.liquidityGrossAfterLower) = updateTick(self, tickLower, liquidityDelta, false);
            (state.flippedUpper, state.liquidityGrossAfterUpper) = updateTick(self, tickUpper, liquidityDelta, true);

            if (liquidityDelta >= 0) {
                uint128 maxLiquidityPerTick = TickMath.tickSpacingToMaxLiquidityPerTick(params.tickSpacing);

                if (state.liquidityGrossAfterLower > maxLiquidityPerTick) {
                    revert IPoolManager.TickLiquidityOverflow(tickLower);
                }
                if (state.liquidityGrossAfterUpper > maxLiquidityPerTick) {
                    revert IPoolManager.TickLiquidityOverflow(tickUpper);
                }

                if (state.flippedLower) {
                    TickBitmap.flipTick(self.tickBitmap, tickLower, params.tickSpacing);
                }
                if (state.flippedUpper) {
                    TickBitmap.flipTick(self.tickBitmap, tickUpper, params.tickSpacing);
                }

                {
                    PositionState storage position =
                        self.positions[keccak256(abi.encode(params.owner, tickLower, tickUpper, params.salt))];
                }

                if (liquidityDelta != 0) {
                    Slot0 _slot0 = self.slot0;
                    (int24 tick, uint160 sqrtPriceX96) = (_slot0.tick(), _slot0.sqrtPriceX96());
                    if (tick < tickLower) {
                        // current tick is below the passed range; liquidity can only become in range by crossing from left to
                        // right, when we'll need _more_ currency0 (it's becoming more valuable) so user must provide it
                        delta = toBalanceDelta(
                            SafeCast.toInt128(
                                SqrtPriceMath.getAmount0Delta(
                                    TickMath.getSqrtPriceAtTick(tickLower),
                                    TickMath.getSqrtPriceAtTick(tickUpper),
                                    liquidityDelta
                                )
                            ),
                            0
                        );
                    } else if (tick < tickUpper) {
                        delta = toBalanceDelta(
                            SafeCast.toInt128(
                                SqrtPriceMath.getAmount0Delta(
                                    sqrtPriceX96, TickMath.getSqrtPriceAtTick(tickUpper), liquidityDelta
                                )
                            ),
                            SafeCast.toInt128(
                                SqrtPriceMath.getAmount1Delta(
                                    TickMath.getSqrtPriceAtTick(tickLower), sqrtPriceX96, liquidityDelta
                                )
                            )
                        );

                        self.liquidity = LiquidityMath.addDelta(self.liquidity, liquidityDelta);
                    } else {
                        // current tick is above the passed range; liquidity can only become in range by crossing from right to
                        // left, when we'll need _more_ currency1 (it's becoming more valuable) so user must provide it
                        delta = toBalanceDelta(
                            0,
                            SafeCast.toInt128(
                                SqrtPriceMath.getAmount1Delta(
                                    TickMath.getSqrtPriceAtTick(tickLower),
                                    TickMath.getSqrtPriceAtTick(tickUpper),
                                    liquidityDelta
                                )
                            )
                        );
                    }
                }
            }
        }
    }
}

/// @dev Common checks for valid tick inputs.
function checkTicks(int24 tickLower, int24 tickUpper) pure {
    if (tickLower >= tickUpper) revert IPoolManager.TicksMisordered(tickLower, tickUpper);
    if (tickLower < TickMath.MIN_TICK) revert IPoolManager.TickLowerOutOfBounds(tickLower);
    if (tickUpper > TickMath.MAX_TICK) revert IPoolManager.TickUpperOutOfBounds(tickUpper);
}

/// @notice Executes a swap against the state, and returns the amount deltas of the pool
/// @dev PoolManager checks that the pool is initialized before calling
function swap(PoolState storage self, SwapParams memory params)
    returns (BalanceDelta swapDelta, uint256 amountToProtocol, uint24 swapFee, SwapResult memory result)
{
    Slot0 slot0Start = self.slot0;
    bool zeroForOne = params.zeroForOne;

    // the amount remaining to be swapped in/out of the input/output asset. initially set to the amountSpecified
    int256 amountSpecifiedRemaining = params.amountSpecified;
    // the amount swapped out/in of the output/input asset. initially set to 0
    int256 amountCalculated = 0;
    // initialize to the current sqrt(price)
    result.sqrtPriceX96 = slot0Start.sqrtPriceX96();
    // initialize to the current tick
    result.tick = slot0Start.tick();
    // initialize to the current liquidity
    result.liquidity = self.liquidity;

    if (zeroForOne) {
        if (params.sqrtPriceLimitX96 >= slot0Start.sqrtPriceX96()) {
            revert IPoolManager.PriceLimitAlreadyExceeded(slot0Start.sqrtPriceX96(), params.sqrtPriceLimitX96);
        }
        // Swaps can never occur at MIN_TICK, only at MIN_TICK + 1, except at initialization of a pool
        // Under certain circumstances outlined below, the tick will preemptively reach MIN_TICK without swapping there
        if (params.sqrtPriceLimitX96 <= TickMath.MIN_SQRT_PRICE) {
            revert IPoolManager.PriceLimitOutOfBounds(params.sqrtPriceLimitX96);
        }
    } else {
        // swap from right to left (token1 to token0)
        if (params.sqrtPriceLimitX96 <= slot0Start.sqrtPriceX96()) {
            revert IPoolManager.PriceLimitAlreadyExceeded(slot0Start.sqrtPriceX96(), params.sqrtPriceLimitX96);
        }

        if (params.sqrtPriceLimitX96 >= TickMath.MAX_SQRT_PRICE) {
            revert IPoolManager.PriceLimitOutOfBounds(params.sqrtPriceLimitX96);
        }
    }
    StepComputations memory step;

    // continue swapping as long as we haven't used the entire input/output and haven't reached the price limit
    while (!(amountSpecifiedRemaining == 0 || result.sqrtPriceX96 == params.sqrtPriceLimitX96)) {
        step.sqrtPriceStartX96 = result.sqrtPriceX96;

        (step.tickNext, step.initialized) =
            TickBitmap.nextInitializedTickWithinOneWord(self.tickBitmap, result.tick, params.tickSpacing, zeroForOne);

        // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
        if (step.tickNext <= TickMath.MIN_TICK) {
            step.tickNext = TickMath.MIN_TICK;
        }
        if (step.tickNext >= TickMath.MAX_TICK) {
            step.tickNext = TickMath.MAX_TICK;
        }
    }
}
