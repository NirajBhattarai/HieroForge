// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {PoolKey} from "hieroforge-core/types/PoolKey.sol";

/// @title IQuoter
/// @notice Interface for quoting exact input/output swap amounts (simulate then revert)
interface IQuoter {
    /// @notice Params for a single-pool quote
    struct QuoteExactSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 exactAmount;
        bytes hookData;
    }

    /// @notice Quotes exact-input single-pool swap. Reverts with QuoteSwap(uint256 amountOut) on success; reverts with other error on failure.
    /// @param params poolKey, zeroForOne, exactAmount, hookData
    function quoteExactInputSingle(QuoteExactSingleParams memory params) external;

    /// @notice Quotes exact-output single-pool swap. Reverts with QuoteSwap(uint256 amountIn) on success; reverts with other error on failure.
    /// @param params poolKey, zeroForOne, exactAmount (output), hookData
    function quoteExactOutputSingle(QuoteExactSingleParams memory params) external;
}
