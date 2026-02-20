// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Currency} from "./Currency.sol";
import {IHooks} from "../interfaces/IHooks.sol";

type PoolId is bytes32;

using {toId} for PoolKey global;

// TODO: use low level function to hash the pool key
function toId(PoolKey memory self) pure returns (PoolId) {
    return PoolId.wrap(keccak256(abi.encode(self.token0, self.token1, self.fee, self.tickSpacing, self.hooks)));
}

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
