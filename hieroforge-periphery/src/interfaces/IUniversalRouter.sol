// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @title IUniversalRouter
/// @notice Interface for the Universal Router (execute encoded commands with deadline)
interface IUniversalRouter {
    /// @notice Thrown when a required command fails
    error ExecutionFailed(uint256 commandIndex, bytes message);

    /// @notice Thrown when sending ETH to the contract in a disallowed way
    error ETHNotAccepted();

    /// @notice Thrown when execution is attempted after the deadline
    error TransactionDeadlinePassed();

    /// @notice Thrown when commands.length != inputs.length
    error LengthMismatch();

    /// @notice Thrown when an unknown command type is dispatched
    error InvalidCommandType(uint256 commandType);

    /// @notice Thrown when SWEEP balance is below minimum
    error InsufficientSweepBalance();

    /// @notice Thrown when native ETH/HBAR sweep fails
    error SweepFailed();

    /// @notice Executes encoded commands with provided inputs. Reverts if deadline has passed.
    /// @param commands Concatenated command bytes (each 1 byte: optional FLAG_ALLOW_REVERT + command type)
    /// @param inputs ABI-encoded inputs for each command (inputs[i] for commands[i])
    /// @param deadline Timestamp by which the transaction must be executed
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}
