// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {TickMath} from "../libraries/TickMath.sol";

/**
 * @dev Slot0 is a packed struct (Uniswap v4-style).
 * Layout: 24 bits empty | 24 bits lpFee | 12 bits protocolFee 1->0 | 12 bits protocolFee 0->1 | 24 bits tick | 160 bits sqrtPriceX96
 */
type Slot0 is bytes32;

using Slot0Library for Slot0 global;

library Slot0Library {
    uint160 internal constant MASK_160_BITS = 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint24 internal constant MASK_24_BITS = 0xFFFFFF;

    uint8 internal constant TICK_OFFSET = 160;
    uint8 internal constant PROTOCOL_FEE_OFFSET = 184;
    uint8 internal constant LP_FEE_OFFSET = 208;

    function sqrtPriceX96(Slot0 _packed) internal pure returns (uint160 _sqrtPriceX96) {
        assembly ("memory-safe") {
            _sqrtPriceX96 := and(MASK_160_BITS, _packed)
        }
    }

    function tick(Slot0 _packed) internal pure returns (int24 _tick) {
        assembly ("memory-safe") {
            _tick := signextend(2, shr(TICK_OFFSET, _packed))
        }
    }

    function protocolFee(Slot0 _packed) internal pure returns (uint24 _protocolFee) {
        assembly ("memory-safe") {
            _protocolFee := and(MASK_24_BITS, shr(PROTOCOL_FEE_OFFSET, _packed))
        }
    }

    function lpFee(Slot0 _packed) internal pure returns (uint24 _lpFee) {
        assembly ("memory-safe") {
            _lpFee := and(MASK_24_BITS, shr(LP_FEE_OFFSET, _packed))
        }
    }

    function setSqrtPriceX96(Slot0 _packed, uint160 _sqrtPriceX96) internal pure returns (Slot0 _result) {
        assembly ("memory-safe") {
            _result := or(and(not(MASK_160_BITS), _packed), and(MASK_160_BITS, _sqrtPriceX96))
        }
    }

    function setTick(Slot0 _packed, int24 _tick) internal pure returns (Slot0 _result) {
        assembly ("memory-safe") {
            _result := or(and(not(shl(TICK_OFFSET, MASK_24_BITS)), _packed), shl(TICK_OFFSET, and(MASK_24_BITS, _tick)))
        }
    }

    function setProtocolFee(Slot0 _packed, uint24 _protocolFee) internal pure returns (Slot0 _result) {
        assembly ("memory-safe") {
            _result := or(
                and(not(shl(PROTOCOL_FEE_OFFSET, MASK_24_BITS)), _packed),
                shl(PROTOCOL_FEE_OFFSET, and(MASK_24_BITS, _protocolFee))
            )
        }
    }

    function setLpFee(Slot0 _packed, uint24 _lpFee) internal pure returns (Slot0 _result) {
        assembly ("memory-safe") {
            _result := or(
                and(not(shl(LP_FEE_OFFSET, MASK_24_BITS)), _packed),
                shl(LP_FEE_OFFSET, and(MASK_24_BITS, _lpFee))
            )
        }
    }
}

/// @notice Builds initial Slot0 from sqrtPriceX96 and lpFee; returns the packed Slot0 and the tick for the given price.
/// @param sqrtPriceX96 Initial sqrt(price) in Q64.96
/// @param lpFee Fee in basis points (e.g. 3000 = 0.3%)
/// @return _slot0 Packed Slot0 with sqrtPriceX96, tick, and lpFee set
/// @return _tick Tick corresponding to sqrtPriceX96 via TickMath.getTickAtSqrtPrice
function initialSlot0(uint160 sqrtPriceX96, uint24 lpFee) pure returns (Slot0 _slot0, int24 _tick) {
    _tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
    _slot0 = Slot0.wrap(bytes32(0)).setSqrtPriceX96(sqrtPriceX96).setTick(_tick).setLpFee(lpFee);
}

/// @notice Returns initial pool state values: Slot0, tick, fee growth globals, and liquidity.
/// @param sqrtPriceX96 Initial sqrt(price) in Q64.96
/// @param lpFee Fee in basis points (e.g. 3000 = 0.3%)
function initialPoolState(uint160 sqrtPriceX96, uint24 lpFee)
    pure
    returns (
        Slot0 _slot0,
        int24 _tick,
        uint256 _feeGrowthGlobal0X128,
        uint256 _feeGrowthGlobal1X128,
        uint128 _liquidity
    )
{
    (_slot0, _tick) = initialSlot0(sqrtPriceX96, lpFee);
    _feeGrowthGlobal0X128 = 1;
    _feeGrowthGlobal1X128 = 1;
    _liquidity = 0;
}
