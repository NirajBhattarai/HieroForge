// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/// @title TickBitmap
/// @notice Library for managing a bitmap of initialized ticks (per tick spacing)
library TickBitmap {
    /// @notice Flips the initialized state for a given tick from false to true, or vice versa
    /// @param self The mapping in which to flip the tick
    /// @param tick The tick to flip
    /// @param tickSpacing The spacing between usable ticks
    function flipTick(mapping(int16 => uint256) storage self, int24 tick, int24 tickSpacing) internal {
        // Equivalent to the following Solidity:
        //     if (tick % tickSpacing != 0) revert TickMisaligned(tick, tickSpacing);
        //     (int16 wordPos, uint8 bitPos) = position(tick / tickSpacing);
        //     uint256 mask = 1 << bitPos;
        //     self[wordPos] ^= mask;
        assembly ("memory-safe") {
            tick := signextend(2, tick)
            tickSpacing := signextend(2, tickSpacing)
            // ensure that the tick is spaced
            if smod(tick, tickSpacing) {
                let fmp := mload(0x40)
                mstore(fmp, 0xd4d8f3e6) // selector for TickMisaligned(int24,int24)
                mstore(add(fmp, 0x20), tick)
                mstore(add(fmp, 0x40), tickSpacing)
                revert(add(fmp, 0x1c), 0x44)
            }
            tick := sdiv(tick, tickSpacing)
            // calculate the storage slot corresponding to the tick
            // wordPos = tick >> 8
            mstore(0, sar(8, tick))
            mstore(0x20, self.slot)
            // the slot of self[wordPos] is keccak256(abi.encode(wordPos, self.slot))
            let slot := keccak256(0, 0x40)
            // mask = 1 << bitPos = 1 << (tick % 256)
            // self[wordPos] ^= mask
            sstore(slot, xor(sload(slot), shl(and(tick, 0xff), 1)))
        }
    }

    /// @notice Computes the position in the mapping where the initialized bit for a tick lives
    /// @param tick The tick for which to compute the position
    /// @return wordPos The key in the mapping containing the word in which the bit is stored
    /// @return bitPos The bit position in the word where the flag is stored
    function position(int24 tick) internal pure returns (int16 wordPos, uint8 bitPos) {
        assembly ("memory-safe") {
            // signed arithmetic shift right
            wordPos := sar(8, signextend(2, tick))
            bitPos := and(tick, 0xff)
        }
    }
}
