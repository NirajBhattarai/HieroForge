// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "../../src/PoolManager.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {TWAPOracleHook} from "../../src/hooks/TWAPOracleHook.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {PoolId} from "../../src/types/PoolId.sol";
import {Currency} from "../../src/types/Currency.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "../../src/types/ModifyLiquidityParams.sol";
import {SwapParams} from "../../src/types/SwapParams.sol";
import {TickMath} from "../../src/libraries/TickMath.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import {Router} from "../utils/Router.sol";
import {Constants} from "../utils/Constants.sol";

/// @notice Tests for TWAPOracleHook
contract TWAPOracleHookTest is Test {
    PoolManager public poolManager;
    Router public router;
    TWAPOracleHook public twapHook;
    MockERC20 public token0;
    MockERC20 public token1;
    PoolKey public key;
    PoolId public poolId;

    /// @dev TWAP hook needs AFTER_INITIALIZE (bit 1) + AFTER_SWAP (bit 5) = 0x22
    uint160 constant TWAP_FLAGS = 0x22;

    function setUp() public {
        poolManager = new PoolManager();
        router = new Router(poolManager);

        // Deploy the TWAP hook implementation
        TWAPOracleHook impl = new TWAPOracleHook(poolManager);

        // Deploy at an address with the correct permission flags (bits 1 and 5)
        address flagged = address((uint160(address(impl)) & ~uint160(0x3F)) | TWAP_FLAGS);
        vm.etch(flagged, address(impl).code);

        // The TWAPOracleHook constructor sets immutable poolManager — we need to ensure
        // storage layout is correct. vm.etch copies code but not storage.
        // However, since poolManager is immutable (stored in bytecode), it will be
        // "wrong" after etch since we're copying from the original address's code.
        // Instead, let's deploy directly to the flagged address.
        // We'll use a different approach: deploy at the exact flagged address using vm.etch
        // and then manually store the poolManager in the immutable slot.
        // Actually, immutables in Solidity ^0.8 are embedded in the runtime bytecode.
        // So vm.etch copies the CORRECT bytecode that has poolManager baked in.
        twapHook = TWAPOracleHook(flagged);

        token0 = new MockERC20();
        token1 = new MockERC20();
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }
        token0.mint(address(this), 1000e18);
        token1.mint(address(this), 1000e18);

        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(twapHook)
        });
        poolId = key.toId();
    }

    function _initPoolAndAddLiquidity() internal {
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);

        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        token0.transfer(address(router), 100e18);
        token1.transfer(address(router), 100e18);

        ModifyLiquidityParams memory liqParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 10e18, salt: bytes32(0)});
        router.modifyLiquidity(key, liqParams, "");
    }

    function _doSwap(bool zeroForOne, uint256 amount) internal returns (BalanceDelta) {
        SwapParams memory params = SwapParams({
            amountSpecified: -int256(amount),
            tickSpacing: 60,
            zeroForOne: zeroForOne,
            sqrtPriceLimitX96: zeroForOne ? TickMath.minSqrtPrice() + 1 : TickMath.maxSqrtPrice() - 1,
            lpFeeOverride: 0
        });
        return router.swap(key, params, "");
    }

    // ─── Tests ─────────────────────────────────────────────────────────────

    function test_afterInitialize_setsFirstObservation() public {
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);

        assertTrue(twapHook.poolInitialized(poolId), "pool should be initialized");
        assertEq(twapHook.getObservationCount(poolId), 1, "should have 1 observation");

        TWAPOracleHook.Observation memory obs = twapHook.getObservation(poolId, 0);
        assertTrue(obs.initialized, "observation should be initialized");
        assertEq(obs.tickCumulative, 0, "initial tickCumulative should be 0");
        assertEq(obs.blockTimestamp, uint32(block.timestamp), "timestamp should be now");
    }

    function test_afterInitialize_setsLastTick() public {
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);
        assertEq(twapHook.lastTick(poolId), 0, "lastTick should be 0 at 1:1 price");
    }

    function test_observationIndex_startsAtOne() public {
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);
        assertEq(twapHook.observationIndex(poolId), 1, "index should be 1 after init");
    }

    function test_afterSwap_addsObservation() public {
        _initPoolAndAddLiquidity();

        uint256 countBefore = twapHook.getObservationCount(poolId);

        // Advance time so tick cumulative changes
        vm.warp(block.timestamp + 60);

        _doSwap(true, 1000);

        assertEq(twapHook.getObservationCount(poolId), countBefore + 1, "should have one more observation");
    }

    function test_afterSwap_tickCumulativeUpdates() public {
        _initPoolAndAddLiquidity();

        // Initial observation has tickCumulative = 0
        TWAPOracleHook.Observation memory obs0 = twapHook.getObservation(poolId, 0);
        assertEq(obs0.tickCumulative, 0);

        // Advance time
        vm.warp(block.timestamp + 120);

        _doSwap(true, 1000);

        TWAPOracleHook.Observation memory obs1 = twapHook.getObservation(poolId, 1);
        assertTrue(obs1.initialized, "new obs should be initialized");
        // tickCumulative = prev.tickCumulative + lastTick * timeDelta
        // lastTick was 0 (from initialize at 1:1), timeDelta = 120
        // So tickCumulative = 0 + 0 * 120 = 0
        assertEq(obs1.tickCumulative, 0, "cumulative = 0 because lastTick was 0");
    }

    function test_observe_returnsLastTick_whenSecondsAgoIsZero() public {
        _initPoolAndAddLiquidity();

        int24 tick = twapHook.observe(poolId, 0);
        assertEq(tick, 0, "observe(0) should return lastTick = 0");
    }

    function test_multipleSwaps_accumulateObservations() public {
        _initPoolAndAddLiquidity();

        // Do 3 swaps with time jumps
        vm.warp(block.timestamp + 60);
        _doSwap(true, 500);

        vm.warp(block.timestamp + 60);
        _doSwap(true, 500);

        vm.warp(block.timestamp + 60);
        _doSwap(false, 500);

        // 1 from init + 3 from swaps = 4
        assertEq(twapHook.getObservationCount(poolId), 4, "should have 4 observations");
    }

    function test_observe_reverts_whenNoObservations() public {
        // Don't initialize pool → no observations
        vm.expectRevert("TWAPOracle: no observations");
        twapHook.observe(poolId, 60);
    }

    function test_lastTick_updatesAfterSwap() public {
        _initPoolAndAddLiquidity();

        int24 tickBefore = twapHook.lastTick(poolId);

        vm.warp(block.timestamp + 60);

        // Large swap to move the price
        _doSwap(true, 1e17);

        int24 tickAfter = twapHook.lastTick(poolId);
        // After a zero-for-one swap, tick should decrease (or stay same if no liquidity crossed)
        assertTrue(tickAfter <= tickBefore, "tick should decrease or stay for zeroForOne swap");
    }

    function test_getHookPermissions_correctFlags() public view {
        Hooks.Permissions memory perms = twapHook.getHookPermissions();
        assertFalse(perms.beforeInitialize);
        assertTrue(perms.afterInitialize);
        assertFalse(perms.beforeModifyLiquidity);
        assertFalse(perms.afterModifyLiquidity);
        assertFalse(perms.beforeSwap);
        assertTrue(perms.afterSwap);
    }
}
