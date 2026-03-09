// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @title IMsgSender
/// @notice Interface for contracts that expose the original executor (e.g. when called via unlock callback)
interface IMsgSender {
    /// @notice Returns the address considered the executor of the current action (e.g. caller of execute())
    function msgSender() external view returns (address);
}
