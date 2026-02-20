// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Slot0} from "./Slot0.sol";
import {TickInfo} from "./TickInfo.sol";
import {PositionState} from "./PositionState.sol";
import {TickMath} from "../libraries/TickMath.sol";

using {initialize} for PoolState global;

struct PoolState {
    Slot0 slot0;
    uint128 liquidity;
    mapping(int24 tick => TickInfo) ticks;
    mapping(int16 wordPos => uint256) tickBitmap;
    mapping(bytes32 positionKey => PositionState) positions;
}

/// @dev PoolState contains mappings and can only be used in storage, not memory.
function initialize(PoolState storage self, uint160 sqrtPriceX96, uint24 lpFee) returns (int24 tick) {
    tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
    self.slot0 = Slot0.wrap(bytes32(0)).setSqrtPriceX96(sqrtPriceX96).setTick(tick).setLpFee(lpFee).setProtocolFee(0);
}
