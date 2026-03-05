// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Lock} from "../../src/libraries/Lock.sol";

/// @notice Harness to expose Lock's internal functions for testing
contract LockHarness {
    function unlock() external {
        Lock.unlock();
    }

    function lock() external {
        Lock.lock();
    }

    function isUnlocked() external view returns (bool) {
        return Lock.isUnlocked();
    }
}

contract LockTest is Test {
    LockHarness public harness;

    function setUp() public {
        harness = new LockHarness();
    }

    // --- Initial state (transient storage is zero = false) ---
    function test_IsUnlocked_InitiallyFalse() public view {
        assertFalse(harness.isUnlocked());
    }

    // --- unlock() ---
    function test_Unlock_SetsUnlockedTrue() public {
        harness.unlock();
        assertTrue(harness.isUnlocked());
    }

    // --- lock() ---
    function test_Lock_SetsUnlockedFalse() public {
        harness.unlock();
        harness.lock();
        assertFalse(harness.isUnlocked());
    }

    function test_Lock_WhenAlreadyLocked_StaysFalse() public {
        harness.lock();
        assertFalse(harness.isUnlocked());
    }

    // --- Toggle ---
    function test_UnlockLock_ToggleMultipleTimes() public {
        assertFalse(harness.isUnlocked());

        harness.unlock();
        assertTrue(harness.isUnlocked());

        harness.lock();
        assertFalse(harness.isUnlocked());

        harness.unlock();
        assertTrue(harness.isUnlocked());

        harness.lock();
        assertFalse(harness.isUnlocked());
    }

    // --- Unlock twice then lock ---
    function test_UnlockTwice_ThenLock_IsFalse() public {
        harness.unlock();
        harness.unlock();
        assertTrue(harness.isUnlocked());
        harness.lock();
        assertFalse(harness.isUnlocked());
    }

    // --- Lock twice ---
    function test_LockTwice_StaysFalse() public {
        harness.lock();
        harness.lock();
        assertFalse(harness.isUnlocked());
    }
}
