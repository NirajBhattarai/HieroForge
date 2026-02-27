// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {PoolKey} from "./PoolKey.sol";

type PoolId is bytes32;

/// @notice Library for computing the ID of a pool (Uniswap v4-style)
library PoolIdLibrary {
    /// @notice Returns keccak256(abi.encode(poolKey))
    /// @param poolKey The pool key
    /// @return poolId The unique pool id
    function toId(PoolKey memory poolKey) internal pure returns (PoolId poolId) {
        poolId = PoolId.wrap(keccak256(abi.encode(poolKey)));
    }
}
