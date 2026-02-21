// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {PoolId} from "./types/PoolKey.sol";
import {Currency} from "./types/Currency.sol";
import {MIN_TICK_SPACING, MAX_TICK_SPACING} from "./math/constants.sol";
import {PoolState} from "./types/PoolState.sol";

contract PoolManager is IPoolManager {
    mapping(PoolId id => PoolState) internal _pools;

    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick) {
        // TODO: revert with low level function to save gas
        if (key.tickSpacing < MIN_TICK_SPACING) revert TickSpacingTooSmall(key.tickSpacing);
        if (key.tickSpacing > MAX_TICK_SPACING) revert TickSpacingTooLarge(key.tickSpacing);

        if (Currency.unwrap(key.token0) >= Currency.unwrap(key.token1)) {
            revert CurrenciesOutOfOrderOrEqual(Currency.unwrap(key.token0), Currency.unwrap(key.token1));
        }

        // NOTE: Hooks are not yet wired into the pool. Current flow is create-pool → swap only.
        // Hooks will be added once this minimal path is in place.

        PoolId id = key.toId();
        return 0;
    }
}
