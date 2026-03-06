// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {PoolKey} from "hieroforge-core/types/PoolKey.sol";

/// @title IV4Router
/// @notice Interface for the V4Router contract (HieroForge periphery — swap routing via hieroforge-core)
interface IV4Router {
    // ─────────────────────────────────────────────────────────────────────────────
    // Errors (slippage / validation)
    // ─────────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when an exact-input swap receives less than amountOutMinimum
    error V4TooLittleReceived(uint256 amountOutMinimum, uint256 amountReceived);

    /// @notice Emitted when an exact-output swap requires more than amountInMaximum
    error V4TooMuchRequested(uint256 amountInMaximum, uint256 amountRequested);

    // ─────────────────────────────────────────────────────────────────────────────
    // Param structs (single-hop; multi-hop can be added later)
    // ─────────────────────────────────────────────────────────────────────────────

    /// @notice Parameters for a single-hop exact-input swap
    struct ExactInputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMinimum;
        bytes hookData;
    }

    /// @notice Parameters for a single-hop exact-output swap
    struct ExactOutputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountOut;
        uint128 amountInMaximum;
        bytes hookData;
    }

    // Methods will be added gradually (e.g. swapExactInputSingle, swapExactOutputSingle, etc.)
}
