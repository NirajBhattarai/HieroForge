// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Currency, CurrencyLibrary} from "hieroforge-core/types/Currency.sol";
import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
import {ImmutableState} from "./ImmutableState.sol";
import {ActionConstants} from "../libraries/ActionConstants.sol";

/// @notice Abstract contract used to sync, send, and settle funds to the pool manager
/// @dev Note that sync() is called before any erc-20 transfer in `settle`.
abstract contract DeltaResolver is ImmutableState {
    using CurrencyLibrary for Currency;
    /// @notice Emitted when trying to settle a positive delta.
    error DeltaNotPositive(Currency currency);
    /// @notice Emitted when trying to take a negative delta.
    error DeltaNotNegative(Currency currency);
    /// @notice Emitted when the contract does not have enough balance to wrap or unwrap.
    error InsufficientBalance();

    /// @notice Take an amount of currency out of the PoolManager
    function _take(Currency currency, address recipient, uint256 amount) internal {
        if (amount == 0) return;
        poolManager.take(currency, recipient, amount);
    }

    /// @notice Pay and settle a currency to the PoolManager
    function _settle(Currency currency, address payer, uint256 amount) internal {
        if (amount == 0) return;

        poolManager.sync(currency);
        if (currency.isAddressZero()) {
            poolManager.settle{value: amount}();
        } else {
            _pay(currency, payer, amount);
            poolManager.settle();
        }
    }

    /// @notice Abstract function for contracts to implement paying tokens to the poolManager
    function _pay(Currency token, address payer, uint256 amount) internal virtual;

    /// @notice Obtain the full amount owed by this contract (negative delta)
    function _getFullDebt(Currency currency) internal view returns (uint256 amount) {
        int256 _amount = poolManager.currencyDelta(address(this), currency);
        if (_amount > 0) revert DeltaNotNegative(currency);
        amount = uint256(-_amount);
    }

    /// @notice Obtain the full credit owed to this contract (positive delta)
    function _getFullCredit(Currency currency) internal view returns (uint256 amount) {
        int256 _amount = poolManager.currencyDelta(address(this), currency);
        if (_amount < 0) revert DeltaNotPositive(currency);
        amount = uint256(_amount);
    }

    /// @notice Calculates the amount for a settle action
    function _mapSettleAmount(uint256 amount, Currency currency) internal view returns (uint256) {
        if (amount == ActionConstants.CONTRACT_BALANCE) {
            return currency.balanceOfSelf();
        } else if (amount == ActionConstants.OPEN_DELTA) {
            return _getFullDebt(currency);
        } else {
            return amount;
        }
    }

    /// @notice Calculates the amount for a take action
    function _mapTakeAmount(uint256 amount, Currency currency) internal view returns (uint256) {
        if (amount == ActionConstants.OPEN_DELTA) {
            return _getFullCredit(currency);
        } else {
            return amount;
        }
    }
}
