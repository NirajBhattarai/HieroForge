// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/// @notice Transient storage helper to track the original msg.sender through unlock callbacks.
/// @dev Uses tstore/tload for gas-efficient transient state.
library Locker {
    // bytes32(uint256(keccak256("LockedBy")) - 1)
    bytes32 constant LOCKED_BY_SLOT = 0x0aedd6bde10e3aa2adec092b02a3e3e805795516cda41f27aa145b8f300af87a;

    function set(address locker) internal {
        assembly {
            tstore(LOCKED_BY_SLOT, locker)
        }
    }

    function get() internal view returns (address locker) {
        assembly {
            locker := tload(LOCKED_BY_SLOT)
        }
    }
}
