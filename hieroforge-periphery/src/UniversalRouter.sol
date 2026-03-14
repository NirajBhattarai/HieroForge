// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "hieroforge-core/types/Currency.sol";
import {IERC20Minimal} from "hieroforge-core/interfaces/IERC20Minimal.sol";
import {V4Router} from "./V4Router.sol";
import {Commands} from "./libraries/Commands.sol";
import {IUniversalRouter} from "./interfaces/IUniversalRouter.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";

/// @title UniversalRouter
/// @notice Executes encoded commands (e.g. V4_SWAP, V4_POSITION_CALL, SWEEP) with a deadline
contract UniversalRouter is IUniversalRouter, V4Router {
    using CurrencyLibrary for Currency;

    /// @dev Stores the initiator of execute() so that msgSender() returns it during unlock callback
    address private _executor;

    /// @dev The PositionManager used for V4_POSITION_CALL
    IPositionManager public immutable positionManager;

    constructor(IPoolManager _poolManager, IPositionManager _positionManager) V4Router(_poolManager) {
        positionManager = _positionManager;
    }

    /// @inheritdoc IUniversalRouter
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable {
        if (block.timestamp > deadline) revert TransactionDeadlinePassed();
        _executor = msg.sender;
        execute(commands, inputs);
        _executor = address(0);
    }

    /// @notice Internal execution loop: dispatches each command with its input
    function execute(bytes calldata commands, bytes[] calldata inputs) public {
        uint256 numCommands = commands.length;
        if (inputs.length != numCommands) revert LengthMismatch();

        address prevExecutor = _executor;
        _executor = msg.sender;

        for (uint256 i = 0; i < numCommands; i++) {
            bytes1 command = commands[i];
            bytes calldata input = inputs[i];

            (bool success, bytes memory output) = dispatch(command, input);

            if (!success && successRequired(command)) {
                _executor = prevExecutor;
                revert ExecutionFailed({commandIndex: i, message: output});
            }
        }
        _executor = prevExecutor;
    }

    /// @notice Returns the executor (caller of execute())
    function msgSender() public view override returns (address) {
        if (_executor != address(0)) return _executor;
        return msg.sender;
    }

    /// @notice Dispatches a single command with its input
    function dispatch(bytes1 command, bytes calldata input) internal returns (bool success, bytes memory output) {
        uint256 commandType = uint8(command & Commands.COMMAND_TYPE_MASK);
        success = true;

        if (commandType == Commands.V4_SWAP) {
            (bool ok, bytes memory data) =
                address(this).call(abi.encodeWithSelector(this.executeV4Swap.selector, input));
            if (!ok) {
                if (successRequired(command)) _revertWithBytes(data);
                success = false;
                output = data;
            }
            return (success, output);
        }

        if (commandType == Commands.V4_POSITION_CALL) {
            (bytes memory unlockData, uint256 deadline) = abi.decode(input, (bytes, uint256));
            try positionManager.modifyLiquidities(unlockData, deadline) {}
            catch (bytes memory data) {
                if (successRequired(command)) _revertWithBytes(data);
                success = false;
                output = data;
            }
            return (success, output);
        }

        if (commandType == Commands.SWEEP) {
            (address token, address recipient, uint256 amountMin) = abi.decode(input, (address, address, uint256));
            uint256 balance;
            if (token == address(0)) {
                balance = address(this).balance;
                if (balance < amountMin) revert InsufficientSweepBalance();
                if (balance > 0) {
                    (bool sent,) = recipient.call{value: balance}("");
                    if (!sent) revert SweepFailed();
                }
            } else {
                balance = IERC20Minimal(token).balanceOf(address(this));
                if (balance < amountMin) revert InsufficientSweepBalance();
                if (balance > 0) {
                    require(IERC20Minimal(token).transfer(recipient, balance), "SWEEP: transfer failed");
                }
            }
            return (success, output);
        }

        revert InvalidCommandType(commandType);
    }

    function _revertWithBytes(bytes memory result) private pure {
        if (result.length > 0) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
        revert("UniversalRouter: command failed");
    }

    /// @dev External so dispatch can self-call and get revert data; must only be called by this contract
    function executeV4Swap(bytes calldata input) external {
        if (msg.sender != address(this)) revert("UniversalRouter: internal only");
        _executeV4Swap(input);
    }

    function successRequired(bytes1 command) internal pure returns (bool) {
        return (uint8(command) & uint8(Commands.FLAG_ALLOW_REVERT)) == 0;
    }
}
