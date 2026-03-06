// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
import {BalanceDelta} from "hieroforge-core/types/BalanceDelta.sol";
import {IQuoter} from "./interfaces/IQuoter.sol";
import {QuoterRevert} from "./libraries/QuoterRevert.sol";
import {BaseQuoter} from "./base/BaseQuoter.sol";

/// @title Quoter
/// @notice Quotes exact input/output amounts by simulating a swap in unlock and reverting with the result
contract Quoter is IQuoter, BaseQuoter {
    using QuoterRevert for *;

    constructor(IPoolManager _poolManager) BaseQuoter(_poolManager) {}

    /// @inheritdoc IQuoter
    /// @dev Reverts with QuoteSwap(amountOut) on success; any other revert is the underlying failure.
    function quoteExactInputSingle(QuoteExactSingleParams memory params) external {
        poolManager.unlock(abi.encodeCall(this._quoteExactInputSingle, (params)));
    }

    /// @inheritdoc IQuoter
    /// @dev Reverts with QuoteSwap(amountIn) on success; any other revert is the underlying failure.
    function quoteExactOutputSingle(QuoteExactSingleParams memory params) external {
        poolManager.unlock(abi.encodeCall(this._quoteExactOutputSingle, (params)));
    }

    /// @dev Called inside unlock callback: simulate exact-in swap, then revert with amountOut
    function _quoteExactInputSingle(QuoteExactSingleParams calldata params) external selfOnly returns (bytes memory) {
        BalanceDelta swapDelta =
            _swap(params.poolKey, params.zeroForOne, -int256(int128(params.exactAmount)), params.hookData);
        uint256 amountOut =
            params.zeroForOne ? uint128(int128(swapDelta.amount1())) : uint128(int128(swapDelta.amount0()));
        amountOut.revertQuote();
    }

    /// @dev Called inside unlock callback: simulate exact-out swap, then revert with amountIn
    function _quoteExactOutputSingle(QuoteExactSingleParams calldata params) external selfOnly returns (bytes memory) {
        BalanceDelta swapDelta =
            _swap(params.poolKey, params.zeroForOne, int256(uint256(params.exactAmount)), params.hookData);
        uint256 amountIn =
            params.zeroForOne ? uint128(-int128(swapDelta.amount0())) : uint128(-int128(swapDelta.amount1()));
        amountIn.revertQuote();
    }
}
