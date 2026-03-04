// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {NonzeroDeltaCount} from "../../src/libraries/NonzeroDeltaCount.sol";

/// @notice Harness to expose NonzeroDeltaCount's internal functions for testing
contract NonzeroDeltaCountHarness {
    function read() external view returns (uint256) {
        return NonzeroDeltaCount.read();
    }

    function increment() external {
        NonzeroDeltaCount.increment();
    }

    function decrement() external {
        NonzeroDeltaCount.decrement();
    }
}

contract NonzeroDeltaCountTest is Test {
    NonzeroDeltaCountHarness public harness;

    function setUp() public {
        harness = new NonzeroDeltaCountHarness();
    }

    // --- Initial state (transient storage is zero) ---
    function test_Read_InitiallyZero() public view {
        assertEq(harness.read(), 0);
    }

    // --- increment() ---
    function test_Increment_FromZero_ReadReturnsOne() public {
        harness.increment();
        assertEq(harness.read(), 1);
    }

    function test_Increment_MultipleTimes() public {
        harness.increment();
        harness.increment();
        harness.increment();
        assertEq(harness.read(), 3);
    }

    // --- decrement() ---
    function test_Decrement_AfterIncrement_ReturnsZero() public {
        harness.increment();
        harness.decrement();
        assertEq(harness.read(), 0);
    }

    function test_Decrement_MultipleTimes() public {
        harness.increment();
        harness.increment();
        harness.increment();
        harness.decrement();
        harness.decrement();
        assertEq(harness.read(), 1);
    }

    // --- increment/decrement balance ---
    function test_IncrementDecrement_BackToZero() public {
        harness.increment();
        harness.increment();
        harness.decrement();
        harness.decrement();
        assertEq(harness.read(), 0);
    }

    // --- Decrement from zero underflows (library does not check; integrating contracts must ensure) ---
    function test_Decrement_FromZero_UnderflowsToMax() public {
        harness.decrement();
        assertEq(harness.read(), type(uint256).max);
    }

    // --- Fuzz: n increments then n decrements yields 0 ---
    function testFuzz_IncrementThenDecrementSameTimes_ReturnsZero(uint8 n) public {
        for (uint256 i; i < n; i++) {
            harness.increment();
        }
        for (uint256 i; i < n; i++) {
            harness.decrement();
        }
        assertEq(harness.read(), 0);
    }

    // --- Fuzz: read equals number of increments minus decrements ---
    function testFuzz_ReadEqualsIncrementsMinusDecrements(uint8 incs, uint8 decs) public {
        vm.assume(incs >= decs);
        for (uint256 i; i < incs; i++) {
            harness.increment();
        }
        for (uint256 i; i < decs; i++) {
            harness.decrement();
        }
        assertEq(harness.read(), incs - decs);
    }
}
