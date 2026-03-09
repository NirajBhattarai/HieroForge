// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "hieroforge-core/callback/IUnlockCallback.sol";
import {ImmutableState} from "./ImmutableState.sol";
import {CalldataDecoder} from "../libraries/CalldataDecoder.sol";
import {SafeCallback} from "./SafeCallback.sol";
import {ActionConstants} from "../libraries/ActionConstants.sol";
import {IMsgSender} from "../interfaces/IMsgSender.sol";

abstract contract BaseActionsRouter is IMsgSender, SafeCallback {
    using CalldataDecoder for bytes;

    /// @notice Thrown when different numbers of parameters and actions are provided
    error InputLengthMismatch();

    /// @notice Thrown when an inheriting contract does not support an action
    error UnsupportedAction(uint256 action);

    constructor(IPoolManager _poolManager) SafeCallback(_poolManager) {}

    /// @notice Returns the address considered executor of the actions (override in UniversalRouter to return execute() caller)
    function msgSender() public view virtual returns (address) {
        return msg.sender;
    }

    /// @notice Maps recipient placeholder to actual address
    function _mapRecipient(address recipient) internal view returns (address) {
        if (recipient == ActionConstants.MSG_SENDER) {
            return msgSender();
        } else if (recipient == ActionConstants.ADDRESS_THIS) {
            return address(this);
        } else {
            return recipient;
        }
    }

    /// @notice Maps payer flag to actual address
    function _mapPayer(bool payerIsUser) internal view returns (address) {
        return payerIsUser ? msgSender() : address(this);
    }

    /// @notice internal function that triggers the execution of a set of actions on v4
    /// @dev inheriting contracts should call this function to trigger execution
    function _executeActions(bytes calldata unlockData) internal {
        poolManager.unlock(unlockData);
    }

    /// @notice function that is called by the PoolManager through the SafeCallback.unlockCallback
    /// @param data Abi encoding of (bytes actions, bytes[] params)
    /// where params[i] is the encoded parameters for actions[i]
    function _unlockCallback(bytes calldata data) internal override returns (bytes memory) {
        // abi.decode(data, (bytes, bytes[]));
        (bytes calldata actions, bytes[] calldata params) = data.decodeActionsRouterParams();
        _executeActionsWithoutUnlock(actions, params);
        return "";
    }

    function _executeActionsWithoutUnlock(bytes calldata actions, bytes[] calldata params) internal {
        uint256 numActions = actions.length;
        if (numActions != params.length) revert InputLengthMismatch();

        for (uint256 actionIndex = 0; actionIndex < numActions; actionIndex++) {
            uint256 action = uint8(actions[actionIndex]);

            _handleAction(action, params[actionIndex]);
        }
    }

    /// @notice function to handle the parsing and execution of an action and its parameters
    function _handleAction(uint256 action, bytes calldata params) internal virtual;
}
