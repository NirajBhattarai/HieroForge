// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @title IUnlockCallback
/// @notice Callback invoked by PoolManager.unlock; caller must settle currency in the callback
interface IUnlockCallback {
    /// @param data Data passed to unlock()
    /// @return result Return value from the callback
    function unlockCallback(bytes calldata data) external returns (bytes memory result);
}
