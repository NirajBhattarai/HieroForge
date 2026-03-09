// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IPositionManager
/// @notice Interface for the PositionManager contract
interface IPositionManager {
    /// @notice Thrown when the block.timestamp exceeds the user-provided deadline
    error DeadlinePassed(uint256 deadline);
    /// @notice Unlocks Uniswap v4 PoolManager and batches actions for modifying liquidity
    /// @dev This is the standard entrypoint for the PositionManager
    /// @param unlockData is an encoding of actions, and parameters for those actions
    /// @param deadline is the deadline for the batched actions to be executed
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
}
