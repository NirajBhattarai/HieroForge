// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Currency} from "hieroforge-core/types/Currency.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";

struct PathKey {
    Currency intermediateCurrency;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
    bytes hookData;
}

using PathKeyLibrary for PathKey global;

/// @title PathKey Library
/// @notice Functions for working with PathKeys in multi-hop swap paths
library PathKeyLibrary {
    /// @notice Get the pool and swap direction for a given PathKey
    /// @param params the given PathKey
    /// @param currencyIn the input currency
    /// @return poolKey the pool key of the swap
    /// @return zeroForOne the direction of the swap, true if currency0 is being swapped for currency1
    function getPoolAndSwapDirection(PathKey calldata params, Currency currencyIn)
        internal
        pure
        returns (PoolKey memory poolKey, bool zeroForOne)
    {
        Currency currencyOut = params.intermediateCurrency;
        (Currency currency0, Currency currency1) = Currency.unwrap(currencyIn) < Currency.unwrap(currencyOut)
            ? (currencyIn, currencyOut)
            : (currencyOut, currencyIn);

        zeroForOne = Currency.unwrap(currencyIn) == Currency.unwrap(currency0);
        poolKey = PoolKey(currency0, currency1, params.fee, params.tickSpacing, params.hooks);
    }

    /// @notice Same as above but accepts memory PathKey (used for multi-hop decoded from abi.decode)
    function getPoolAndSwapDirectionMemory(PathKey memory params, Currency currencyIn)
        internal
        pure
        returns (PoolKey memory poolKey, bool zeroForOne)
    {
        Currency currencyOut = params.intermediateCurrency;
        (Currency currency0, Currency currency1) = Currency.unwrap(currencyIn) < Currency.unwrap(currencyOut)
            ? (currencyIn, currencyOut)
            : (currencyOut, currencyIn);

        zeroForOne = Currency.unwrap(currencyIn) == Currency.unwrap(currency0);
        poolKey = PoolKey(currency0, currency1, params.fee, params.tickSpacing, params.hooks);
    }
}
