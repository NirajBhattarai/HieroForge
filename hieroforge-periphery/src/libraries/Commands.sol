// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @title Commands
/// @notice Command flags and types for UniversalRouter
library Commands {
    /// @notice If set, command may revert without failing the entire execute batch
    bytes1 internal constant FLAG_ALLOW_REVERT = 0x80;

    /// @notice Mask to extract the 7-bit command type (ignores allow-revert flag)
    bytes1 internal constant COMMAND_TYPE_MASK = 0x7f;

    /// @notice Execute a v4 swap via V4Router (payload passed to _executeV4Swap)
    uint256 internal constant V4_SWAP = 0x10;

    /// @notice Execute a v4 position manager call (payload passed to PositionManager.modifyLiquidities)
    uint256 internal constant V4_POSITION_CALL = 0x11;

    /// @notice Sweep the contract's balance of a token to a recipient
    uint256 internal constant SWEEP = 0x12;
}
