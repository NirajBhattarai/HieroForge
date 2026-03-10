// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {TickBitmap} from "../src/libraries/TickBitmap.sol";
import {console} from "forge-std/console.sol";

contract TickBitmapTest is Test {
    mapping(int16 => uint256) tickBitmap;

    using TickBitmap for mapping(int16 => uint256);

    /// @dev Test nextInitializedTickWithinOneWord with lte=true (search left/current) and lte=false (search right).
    ///      Uses tickSpacing=60 and initializes ticks at -120, 0, 120.
    function test_nextInitializedTickWithinOneWord() public {
        int24 tickSpacing = 60;

        // Initialize ticks at -120, 0, 120 (boundaries; compressed indices -2, 0, 2)
        tickBitmap.flipTick(-120, tickSpacing);
        tickBitmap.flipTick(-60, tickSpacing);
        tickBitmap.flipTick(0, tickSpacing);
        tickBitmap.flipTick(60, tickSpacing);
        tickBitmap.flipTick(120, tickSpacing);

        // --- lte=true: next initialized tick <= starting tick (search "left" in price / lower tick) ---

        // From tick 100: compressed=1; in same word, initialized at 0. Expect next = 0.
        // (int24 next, bool initialized) = tickBitmap.nextInitializedTickWithinOneWord(110, tickSpacing, true);
        // console.log("next--->", next);
        // console.log("initialized--->", initialized);
        // assertTrue(initialized, "should find initialized tick");
        // assertEq(next, 0, "next tick lte from 100 should be 0");

        // // From tick 60: compressed=1; next initialized at or left is 0.
        // (next, initialized) = tickBitmap.nextInitializedTickWithinOneWord(60, tickSpacing, true);
        // assertTrue(initialized);
        // assertEq(next, 0);

        // // From tick 0: next at or left is 0 (itself).
        // (next, initialized) = tickBitmap.nextInitializedTickWithinOneWord(0, tickSpacing, true);
        // assertTrue(initialized);
        // assertEq(next, 0);

        // // From tick -60: compressed=-1; next at or left is -120 (in same word).
        // (next, initialized) = tickBitmap.nextInitializedTickWithinOneWord(-60, tickSpacing, true);
        // assertTrue(initialized);
        // assertEq(next, -120);

        // // --- lte=false: next initialized tick > starting tick (search "right" / higher tick) ---

        // From tick 1 with lte=false: next initialized tick to the right. Compressed 1 is in word 0;
        // initialized ticks in that word include 60 (bit 1) and 120 (bit 2). Next to the right of 1 is 60.
        (int24 next, bool initialized) = tickBitmap.nextInitializedTickWithinOneWord(1, tickSpacing, false);
        assertTrue(initialized);
        assertEq(next, 60);

        // // From tick 60: next above is 120.
        // (next, initialized) = tickBitmap.nextInitializedTickWithinOneWord(60, tickSpacing, false);
        // assertTrue(initialized);
        // assertEq(next, 120);

        // // From tick -60: next above -60 in same word is 0.
        // (next, initialized) = tickBitmap.nextInitializedTickWithinOneWord(-60, tickSpacing, false);
        // assertTrue(initialized);
        // assertEq(next, 0);
    }

    // /// @dev When no tick is initialized in the searched word, initialized=false and next is still returned (bound of word).
    // function test_nextInitializedTickWithinOneWord_NoInitializedInWord() public {
    //     int24 tickSpacing = 60;
    //     // Initialize only tick 15360 (compressed 256 -> word 1, bit 0). Word 0 has no initialized ticks.
    //     tickBitmap.flipTick(15360, tickSpacing);

    //     // From tick 60, lte=true: compressed=1, word 0 has no initialized. Should return initialized=false.
    //     (int24 next, bool initialized) = tickBitmap.nextInitializedTickWithinOneWord(60, tickSpacing, true);
    //     assertFalse(initialized, "no initialized tick in word");
    //     assertEq(next, 0, "next is left bound of word when none initialized");

    //     // From tick 0, lte=false: start from compressed 1, word 0 has no initialized. Should return initialized=false.
    //     (next, initialized) = tickBitmap.nextInitializedTickWithinOneWord(0, tickSpacing, false);
    //     assertFalse(initialized);
    //     assertEq(
    //         next, 15300, "next is right bound of word when none initialized (compressed + (255-bitPos))*tickSpacing"
    //     );
    // }
}
