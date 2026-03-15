// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {BaseHook} from "../base/BaseHook.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {PoolManager} from "../PoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {PoolId} from "../types/PoolId.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {SwapParams} from "../types/SwapParams.sol";
import {Hooks} from "../libraries/Hooks.sol";

/// @title TWAPOracleHook
/// @notice Records cumulative tick values after each swap for on-chain TWAP queries.
/// @dev Uses a ring buffer of observations per pool. Deploy at an address whose lower 6 bits
///      encode AFTER_INITIALIZE (bit 1) and AFTER_SWAP (bit 5) = 0x22.
///      Adapted for Hedera — no EIP-712 permit dependency.
contract TWAPOracleHook is BaseHook {
    struct Observation {
        uint32 blockTimestamp;
        int56 tickCumulative;
        bool initialized;
    }

    uint256 public constant MAX_OBSERVATIONS = 720;

    /// @notice Pool-specific observation ring buffers
    mapping(PoolId => Observation[]) public observations;

    /// @notice Index of the next observation to write (per pool)
    mapping(PoolId => uint256) public observationIndex;

    /// @notice Last recorded tick per pool (used to compute cumulative values)
    mapping(PoolId => int24) public lastTick;

    /// @notice Whether a pool has been initialized through this hook
    mapping(PoolId => bool) public poolInitialized;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeModifyLiquidity: false,
            afterModifyLiquidity: false,
            beforeSwap: false,
            afterSwap: true
        });
    }

    // ─── Hook callbacks ────────────────────────────────────────────────────

    function afterInitialize(address, PoolKey calldata key, uint160, int24 tick, bytes calldata)
        external
        override
        onlyPoolManager
        returns (bytes4)
    {
        PoolId id = key.toId();
        poolInitialized[id] = true;
        lastTick[id] = tick;

        // Push the first observation
        observations[id].push(
            Observation({blockTimestamp: uint32(block.timestamp), tickCumulative: 0, initialized: true})
        );
        observationIndex[id] = 1;

        return IHooks.afterInitialize.selector;
    }

    function afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        override
        onlyPoolManager
        returns (bytes4, int128)
    {
        PoolId id = key.toId();
        require(poolInitialized[id], "TWAPOracle: pool not initialized");

        uint256 idx = observationIndex[id];
        uint256 prevIdx = idx == 0 ? observations[id].length - 1 : idx - 1;
        Observation memory prev = observations[id][prevIdx];

        uint32 timeDelta = uint32(block.timestamp) - prev.blockTimestamp;
        int56 tickCumulative = prev.tickCumulative + int56(lastTick[id]) * int56(int32(timeDelta));

        Observation memory obs =
            Observation({blockTimestamp: uint32(block.timestamp), tickCumulative: tickCumulative, initialized: true});

        // Write into ring buffer
        if (idx < observations[id].length) {
            observations[id][idx] = obs;
        } else {
            observations[id].push(obs);
        }

        // Update index (wrap around)
        observationIndex[id] = (idx + 1) % MAX_OBSERVATIONS;

        // Update lastTick from pool state
        (, uint160 sqrtPriceX96After, int24 tickAfter) = PoolManager(address(poolManager)).getPoolState(id);
        lastTick[id] = tickAfter;

        return (IHooks.afterSwap.selector, 0);
    }

    // ─── Query functions ───────────────────────────────────────────────────

    /// @notice Get the number of observations recorded for a pool
    function getObservationCount(PoolId id) external view returns (uint256) {
        return observations[id].length;
    }

    /// @notice Get a specific observation
    function getObservation(PoolId id, uint256 index) external view returns (Observation memory) {
        return observations[id][index];
    }

    /// @notice Compute the arithmetic mean tick over the period from `secondsAgo` to now.
    /// @param id The pool ID
    /// @param secondsAgo How far back to look (in seconds)
    /// @return arithmeticMeanTick The TWAP tick value
    function observe(PoolId id, uint32 secondsAgo) external view returns (int24 arithmeticMeanTick) {
        require(observations[id].length > 0, "TWAPOracle: no observations");

        if (secondsAgo == 0) {
            // Return the last recorded tick
            return lastTick[id];
        }

        // Find the observation closest to `secondsAgo` in the past
        uint256 len = observations[id].length;
        uint256 targetTime = block.timestamp - secondsAgo;

        // Linear scan from newest to oldest to find the bracketing observation
        uint256 latestIdx = observationIndex[id] == 0 ? len - 1 : observationIndex[id] - 1;
        Observation memory latest = observations[id][latestIdx];

        // If target is at or after the latest, use latest
        if (targetTime >= latest.blockTimestamp) {
            // Extrapolate from latest
            uint32 elapsed = uint32(block.timestamp) - latest.blockTimestamp;
            int56 currentCumulative = latest.tickCumulative + int56(lastTick[id]) * int56(int32(elapsed));
            int56 targetCumulative = latest.tickCumulative;

            arithmeticMeanTick = int24((currentCumulative - targetCumulative) / int56(int32(secondsAgo)));
            return arithmeticMeanTick;
        }

        // Search backwards for the closest observation before targetTime
        uint256 oldIdx = latestIdx;
        for (uint256 i = 0; i < len; i++) {
            uint256 checkIdx = oldIdx == 0 ? len - 1 : oldIdx - 1;
            if (!observations[id][checkIdx].initialized) break;
            if (observations[id][checkIdx].blockTimestamp <= targetTime) {
                // Found the bracket: [checkIdx, oldIdx]
                Observation memory obsOld = observations[id][checkIdx];
                Observation memory obsNew = observations[id][oldIdx];
                int56 deltaCumulative = obsNew.tickCumulative - obsOld.tickCumulative;
                uint32 deltaTime = obsNew.blockTimestamp - obsOld.blockTimestamp;
                if (deltaTime == 0) return lastTick[id];
                return int24(deltaCumulative / int56(int32(deltaTime)));
            }
            oldIdx = checkIdx;
        }

        // If we get here, all observations are after targetTime; use the oldest
        uint256 oldestIdx = observationIndex[id] < len ? observationIndex[id] : 0;
        Observation memory oldest = observations[id][oldestIdx];
        int56 totalDelta = latest.tickCumulative - oldest.tickCumulative;
        uint32 totalTime = latest.blockTimestamp - oldest.blockTimestamp;
        if (totalTime == 0) return lastTick[id];
        return int24(totalDelta / int56(int32(totalTime)));
    }
}
