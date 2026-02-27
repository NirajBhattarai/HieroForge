// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @title Library for reverting with custom errors efficiently
/// @notice Use with `using CustomRevert for bytes4;` then `Error.selector.revertWith(arg)`
library CustomRevert {
    /// @dev Reverts with a custom error with an int24 argument in the scratch space
    function revertWith(bytes4 selector, int24 value) internal pure {
        assembly ("memory-safe") {
            mstore(0, selector)
            mstore(0x04, signextend(2, value))
            revert(0, 0x24)
        }
    }
}
