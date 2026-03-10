// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {BitMath} from "../../src/libraries/BitMath.sol";

contract BitMathHarness {
    function mostSignificantBit(uint256 x) external pure returns (uint8) {
        return BitMath.mostSignificantBit(x);
    }
}

contract BitMathTest is Test {
    BitMathHarness public harness;

    function setUp() public {
        harness = new BitMathHarness();
    }

    // --- Zero (revert) ---
    function test_MostSignificantBit_RevertWhen_Zero() public {
        // BitMath uses require(x > 0) which reverts with no data
        vm.expectRevert();
        harness.mostSignificantBit(0);
    }

    // --- Single bit set (MSB index = bit index) ---
    function test_MostSignificantBit_SingleBit_Bit0() public view {
        assertEq(harness.mostSignificantBit(1), 0);
    }

    function test_MostSignificantBit_SingleBit_Bit1() public view {
        assertEq(harness.mostSignificantBit(2), 1);
    }

    function test_MostSignificantBit_SingleBit_Bit7() public view {
        assertEq(harness.mostSignificantBit(128), 7);
    }

    function test_MostSignificantBit_SingleBit_Bit8() public view {
        assertEq(harness.mostSignificantBit(256), 8);
    }

    function test_MostSignificantBit_SingleBit_Bit15() public view {
        assertEq(harness.mostSignificantBit(1 << 15), 15);
    }

    function test_MostSignificantBit_SingleBit_Bit31() public view {
        assertEq(harness.mostSignificantBit(1 << 31), 31);
    }

    function test_MostSignificantBit_SingleBit_Bit63() public view {
        assertEq(harness.mostSignificantBit(1 << 63), 63);
    }

    function test_MostSignificantBit_SingleBit_Bit64() public view {
        assertEq(harness.mostSignificantBit(1 << 64), 64);
    }

    function test_MostSignificantBit_SingleBit_Bit127() public view {
        assertEq(harness.mostSignificantBit(1 << 127), 127);
    }

    function test_MostSignificantBit_SingleBit_Bit128() public view {
        assertEq(harness.mostSignificantBit(1 << 128), 128);
    }

    function test_MostSignificantBit_SingleBit_Bit200() public view {
        assertEq(harness.mostSignificantBit(1 << 200), 200);
    }

    function test_MostSignificantBit_SingleBit_Bit254() public view {
        assertEq(harness.mostSignificantBit(1 << 254), 254);
    }

    function test_MostSignificantBit_SingleBit_Bit255() public view {
        assertEq(harness.mostSignificantBit(1 << 255), 255);
    }

    // --- All bits set up to N (MSB = N) ---
    function test_MostSignificantBit_AllBitsSetUpTo7() public view {
        assertEq(harness.mostSignificantBit(type(uint8).max), 7);
    }

    function test_MostSignificantBit_AllBitsSetUpTo15() public view {
        assertEq(harness.mostSignificantBit(type(uint16).max), 15);
    }

    function test_MostSignificantBit_AllBitsSetUpTo31() public view {
        assertEq(harness.mostSignificantBit(type(uint32).max), 31);
    }

    function test_MostSignificantBit_AllBitsSetUpTo63() public view {
        assertEq(harness.mostSignificantBit(type(uint64).max), 63);
    }

    function test_MostSignificantBit_AllBitsSetUpTo127() public view {
        assertEq(harness.mostSignificantBit(type(uint128).max), 127);
    }

    function test_MostSignificantBit_AllBitsSetUpTo255() public view {
        assertEq(harness.mostSignificantBit(type(uint256).max), 255);
    }

    // --- Non-power-of-two (MSB still highest set bit) ---
    function test_MostSignificantBit_NonPow2_Three() public view {
        assertEq(harness.mostSignificantBit(3), 1); // 0b11
    }

    function test_MostSignificantBit_NonPow2_Five() public view {
        assertEq(harness.mostSignificantBit(5), 2); // 0b101
    }

    function test_MostSignificantBit_NonPow2_OneLessThanPow2() public view {
        assertEq(harness.mostSignificantBit((1 << 100) - 1), 99);
    }

    function test_MostSignificantBit_NonPow2_OneMoreThanPow2() public view {
        // (1 << 50) + 1 => MSB still 50
        assertEq(harness.mostSignificantBit((1 << 50) + 1), 50);
    }

    // --- Boundaries and common values ---
    function test_MostSignificantBit_255() public view {
        assertEq(harness.mostSignificantBit(255), 7);
    }

    function test_MostSignificantBit_256() public view {
        assertEq(harness.mostSignificantBit(256), 8);
    }

    function test_MostSignificantBit_257() public view {
        assertEq(harness.mostSignificantBit(257), 8);
    }

    function test_MostSignificantBit_HalfMaxUint256() public view {
        assertEq(harness.mostSignificantBit(type(uint256).max >> 1), 254);
    }

    function test_MostSignificantBit_MaxMinusOne() public view {
        assertEq(harness.mostSignificantBit(type(uint256).max - 1), 255);
    }

    // --- Fuzz: MSB of x equals floor(log2(x)) ---
    function testFuzz_MostSignificantBit_EqualsFloorLog2(uint256 x) public {
        vm.assume(x > 0);
        uint8 msb = harness.mostSignificantBit(x);
        assertTrue((uint256(1) << msb) <= x, "2^msb <= x");
        assertTrue(msb == 255 || (uint256(1) << (msb + 1)) > x, "2^(msb+1) > x");
    }

    // --- Fuzz: single-bit values ---
    function testFuzz_MostSignificantBit_SingleBit(uint8 bitIndex) public {
        uint256 x = uint256(1) << bitIndex;
        assertEq(harness.mostSignificantBit(x), bitIndex);
    }
}
