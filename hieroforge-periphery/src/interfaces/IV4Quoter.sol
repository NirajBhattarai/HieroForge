// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {Currency} from "hieroforge-core/types/Currency.sol";
import {PathKey} from "../libraries/PathKey.sol";
import {IImmutableState} from "./IImmutableState.sol";
import {IMsgSender} from "./IMsgSender.sol";

/// @title IV4Quoter
/// @notice Interface for the V4Quoter contract (matches Uniswap v4 V4Quoter)
interface IV4Quoter is IImmutableState, IMsgSender {
    struct QuoteExactSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 exactAmount;
        bytes hookData;
    }

    struct QuoteExactParams {
        Currency exactCurrency;
        PathKey[] path;
        uint128 exactAmount;
    }

    /// @notice Returns the delta amounts for a given exact input swap of a single pool
    /// @param params The params for the quote, encoded as `QuoteExactSingleParams`
    /// @return amountOut The output quote for the exactIn swap
    /// @return gasEstimate Estimated gas units used for the swap
    function quoteExactInputSingle(QuoteExactSingleParams memory params)
        external
        returns (uint256 amountOut, uint256 gasEstimate);

    /// @notice Returns the delta amounts along the swap path for a given exact input swap
    /// @param params the params for the quote, encoded as 'QuoteExactParams'
    /// @return amountOut The output quote for the exactIn swap
    /// @return gasEstimate Estimated gas units used for the swap
    function quoteExactInput(QuoteExactParams memory params) external returns (uint256 amountOut, uint256 gasEstimate);

    /// @notice Returns the delta amounts for a given exact output swap of a single pool
    /// @param params The params for the quote, encoded as `QuoteExactSingleParams`
    /// @return amountIn The input quote for the exactOut swap
    /// @return gasEstimate Estimated gas units used for the swap
    function quoteExactOutputSingle(QuoteExactSingleParams memory params)
        external
        returns (uint256 amountIn, uint256 gasEstimate);

    /// @notice Returns the delta amounts along the swap path for a given exact output swap
    /// @param params the params for the quote, encoded as 'QuoteExactParams'
    /// @return amountIn The input quote for the exactOut swap
    /// @return gasEstimate Estimated gas units used for the swap
    function quoteExactOutput(QuoteExactParams memory params) external returns (uint256 amountIn, uint256 gasEstimate);
}
