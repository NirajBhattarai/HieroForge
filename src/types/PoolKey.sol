// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Currency} from "./Currency.sol";
import {IHooks} from "../interfaces/IHooks.sol";

/// @notice Unique identifier for a pool containing token addresses and configuration
/// @dev Each pool has its own state associated with this key
struct PoolKey {
    /// @notice The lower currency of the pool, sorted numerically
    Currency token0;
    /// @notice The higher currency of the pool, sorted numerically
    Currency token1;
    /// @notice The fee for the pool
    uint256 fee;
    /// @notice The tick spacing for the pool
    int24 tickSpacing;
    /// @notice The hooks for the pool
    IHooks hooks;
}
