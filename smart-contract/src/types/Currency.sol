// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC20Minimal} from "../interfaces/IERC20Minimal.sol";

/// @notice Currency is address (Uniswap v4-style type for token/ETH)
type Currency is address;

/// @notice Helpers for transfer and balance (PoolManager sync/settle/take)
library CurrencyLibrary {
    function isAddressZero(Currency currency) internal pure returns (bool) {
        return Currency.unwrap(currency) == address(0);
    }

    /// @notice Balance of address(this) for the given currency
    function balanceOfSelf(Currency currency) internal view returns (uint256) {
        if (isAddressZero(currency)) return address(this).balance;
        return IERC20Minimal(Currency.unwrap(currency)).balanceOf(address(this));
    }

    /// @notice Transfer currency from address(this) to recipient
    function transfer(Currency currency, address to, uint256 amount) internal {
        if (isAddressZero(currency)) {
            (bool ok,) = to.call{value: amount}("");
            require(ok, "Currency: native transfer failed");
        } else {
            require(IERC20Minimal(Currency.unwrap(currency)).transfer(to, amount), "Currency: transfer failed");
        }
    }
}

/// @title Library to store callers' currency deltas in transient storage
/// @dev Implements the equivalent of a mapping, as transient storage can only be accessed in assembly
library CurrencyDelta {
    /// @notice Calculates which storage slot a delta should be stored in for a given account and currency
    function _computeSlot(address target, Currency currency) private pure returns (bytes32 hashSlot) {
        assembly ("memory-safe") {
            mstore(0, and(target, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(32, and(currency, 0xffffffffffffffffffffffffffffffffffffffff))
            hashSlot := keccak256(0, 64)
        }
    }

    function getDelta(Currency currency, address target) internal view returns (int256 delta) {
        bytes32 hashSlot = _computeSlot(target, currency);
        assembly ("memory-safe") {
            delta := tload(hashSlot)
        }
    }

    /// @notice Applies a new currency delta for a given account and currency
    /// @return previous The prior value
    /// @return next The modified result
    function applyDelta(Currency currency, address target, int128 delta)
        internal
        returns (int256 previous, int256 next)
    {
        bytes32 hashSlot = _computeSlot(target, currency);
        assembly ("memory-safe") {
            previous := tload(hashSlot)
        }
        next = previous + delta;
        assembly ("memory-safe") {
            tstore(hashSlot, next)
        }
    }
}
