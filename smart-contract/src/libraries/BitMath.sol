// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @title BitMath
/// @dev Provides bit operations for unsigned integers (from Uniswap v4-core / Solady LibBit)
library BitMath {
    /// @notice Returns the index of the most significant bit of the number,
    /// where the least significant bit is at index 0 and the most significant bit is at index 255
    /// @param x The value for which to compute the most significant bit, must be greater than 0
    /// @return r The index of the most significant bit
    function mostSignificantBit(uint256 x) internal pure returns (uint8 r) {
        require(x > 0, "BitMath: zero has no MSB");
        assembly ("memory-safe") {
            r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
            r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
            r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
            r := or(r, shl(4, lt(0xffff, shr(r, x))))
            r := or(r, shl(3, lt(0xff, shr(r, x))))
            r := or(
                r,
                byte(
                    and(0x1f, shr(shr(r, x), 0x8421084210842108cc6318c6db6d54be)),
                    0x0706060506020500060203020504000106050205030304010505030400000000
                )
            )
        }
    }
}
