// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @notice Parameters for swap (Uniswap v4-style)
/// @dev amountSpecified < 0 means exact input; amountSpecified > 0 means exact output
struct SwapParams {
    int256 amountSpecified;
    int24 tickSpacing;
    bool zeroForOne;
    uint160 sqrtPriceLimitX96;
    uint24 lpFeeOverride;
}
