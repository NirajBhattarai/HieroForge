// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "../../src/PoolManager.sol";
import {PoolKey, TokensMustBeSorted, InvalidTickSpacing} from "../../src/types/PoolKey.sol";
import {Currency} from "../../src/types/Currency.sol";
import {PoolId} from "../../src/types/PoolId.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {MIN_TICK_SPACING, MAX_TICK_SPACING} from "../../src/constants.sol";
import {TickMath} from "../../src/libraries/TickMath.sol";
import {Constants} from "../utils/Constants.sol";

// TickMath valid sqrtPrice bounds (from TickMath.sol)
uint160 constant MIN_SQRT_PRICE = 4295128739;
uint160 constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;

/// @notice Comprehensive tests for PoolManager.initialize (Uniswap v4-style).
/// Run: forge test --match-path test/PoolManager/initialize.t.sol
/// Run against local Hedera node: forge test --match-path test/PoolManager/initialize.t.sol --fork-url http://localhost:7546
contract PoolManagerInitializeTest is Test {
    PoolManager public poolManager;

    uint160 internal constant SQRT_PRICE_1_1 = Constants.SQRT_PRICE_1_1;

    function setUp() public {
        poolManager = new PoolManager();
    }

    function _makeKey(address c0, address c1, uint24 fee, int24 tickSpacing) internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: address(0)
        });
    }

    // ---------- Success cases ----------

    function test_Initialize_Succeeds_Price1To1() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, 60);
        int24 tick = poolManager.initialize(key, SQRT_PRICE_1_1);
        assertEq(tick, 0);
        (bool init, uint160 sqrt, int24 t) = poolManager.getPoolState(key.toId());
        assertTrue(init);
        assertEq(sqrt, SQRT_PRICE_1_1);
        assertEq(t, 0);
    }

    function test_Initialize_Succeeds_ReturnedTickMatchesTickMath() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, 60);
        // 887272 (MAX_TICK) yields MAX_SQRT_PRICE which is invalid for getTickAtSqrtPrice; use 887271
        int24[5] memory ticks = [int24(-100), 0, 100, int24(-887272), 887271];
        for (uint256 i = 0; i < ticks.length; i++) {
            uint160 sqrtPrice = TickMath.getSqrtPriceAtTickPublic(ticks[i]);
            poolManager = new PoolManager(); // fresh manager per tick to avoid AlreadyInitialized
            int24 tick = poolManager.initialize(key, sqrtPrice);
            assertEq(tick, ticks[i], "tick mismatch");
        }
    }

    function test_Initialize_Succeeds_AtMinSqrtPrice() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, 60);
        int24 tick = poolManager.initialize(key, MIN_SQRT_PRICE);
        assertEq(tick, -887272); // MIN_TICK
        (, uint160 storedSqrt,) = poolManager.getPoolState(key.toId());
        assertEq(storedSqrt, MIN_SQRT_PRICE);
    }

    function test_Initialize_Succeeds_JustBelowMaxSqrtPrice() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, 60);
        uint160 sqrtJustBelowMax = MAX_SQRT_PRICE - 1;
        int24 tick = poolManager.initialize(key, sqrtJustBelowMax);
        (, uint160 storedSqrt,) = poolManager.getPoolState(key.toId());
        assertEq(storedSqrt, sqrtJustBelowMax);
        assertEq(tick, 887271); // close to MAX_TICK
    }

    function test_Initialize_Succeeds_WithMinTickSpacing() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, MIN_TICK_SPACING);
        int24 tick = poolManager.initialize(key, SQRT_PRICE_1_1);
        assertEq(tick, 0);
        (bool init,,) = poolManager.getPoolState(key.toId());
        assertTrue(init);
    }

    function test_Initialize_Succeeds_WithMaxTickSpacing() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, MAX_TICK_SPACING);
        int24 tick = poolManager.initialize(key, SQRT_PRICE_1_1);
        assertEq(tick, 0);
        (bool init,,) = poolManager.getPoolState(key.toId());
        assertTrue(init);
    }

    function test_Initialize_Succeeds_WithZeroHooks() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 500, 10);
        key.hooks = address(0);
        poolManager.initialize(key, SQRT_PRICE_1_1);
        (bool init,,) = poolManager.getPoolState(key.toId());
        assertTrue(init);
    }

    function test_Initialize_Succeeds_WithNonZeroHooks() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 500, 10);
        key.hooks = address(0xBeef);
        poolManager.initialize(key, SQRT_PRICE_1_1);
        (bool init,,) = poolManager.getPoolState(key.toId());
        assertTrue(init);
    }

    function test_Initialize_Succeeds_DifferentFeesDifferentPools() public {
        PoolKey memory key3 = _makeKey(address(0x1), address(0x2), 3000, 60);
        PoolKey memory key5 = _makeKey(address(0x1), address(0x2), 5000, 60);
        poolManager.initialize(key3, SQRT_PRICE_1_1);
        poolManager.initialize(key5, SQRT_PRICE_1_1);
        (bool init3,,) = poolManager.getPoolState(key3.toId());
        (bool init5,,) = poolManager.getPoolState(key5.toId());
        assertTrue(init3);
        assertTrue(init5);
    }

    function test_Initialize_Succeeds_DifferentCurrenciesDifferentPools() public {
        PoolKey memory keyA = _makeKey(address(0x1), address(0x2), 3000, 60);
        PoolKey memory keyB = _makeKey(address(0x3), address(0x4), 3000, 60);
        poolManager.initialize(keyA, SQRT_PRICE_1_1);
        poolManager.initialize(keyB, SQRT_PRICE_1_1);
        (bool initA,,) = poolManager.getPoolState(keyA.toId());
        (bool initB,,) = poolManager.getPoolState(keyB.toId());
        assertTrue(initA);
        assertTrue(initB);
    }

    function test_Initialize_EmitsInitializeEvent() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, 60);
        PoolId id = key.toId();
        vm.expectEmit(true, true, true, true);
        emit IPoolManager.Initialize(
            id, key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks, SQRT_PRICE_1_1, 0
        );
        poolManager.initialize(key, SQRT_PRICE_1_1);
    }

    // ---------- Revert: validation (PoolKey.validate) ----------

    function test_Initialize_RevertWhen_Currency0GreaterThanCurrency1() public {
        PoolKey memory key = _makeKey(address(0x2), address(0x1), 3000, 60);
        vm.expectRevert(TokensMustBeSorted.selector);
        poolManager.initialize(key, SQRT_PRICE_1_1);
    }

    function test_Initialize_RevertWhen_Currency0EqualsCurrency1() public {
        address same = address(0x100);
        PoolKey memory key = _makeKey(same, same, 3000, 60);
        vm.expectRevert(TokensMustBeSorted.selector);
        poolManager.initialize(key, SQRT_PRICE_1_1);
    }

    function test_Initialize_RevertWhen_TickSpacingBelowMin() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, MIN_TICK_SPACING - 1);
        vm.expectRevert(InvalidTickSpacing.selector);
        poolManager.initialize(key, SQRT_PRICE_1_1);
    }

    function test_Initialize_RevertWhen_TickSpacingAboveMax() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, MAX_TICK_SPACING + 1);
        vm.expectRevert(InvalidTickSpacing.selector);
        poolManager.initialize(key, SQRT_PRICE_1_1);
    }

    // ---------- Revert: already initialized ----------

    function test_Initialize_RevertWhen_AlreadyInitialized() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, 60);
        poolManager.initialize(key, SQRT_PRICE_1_1);
        vm.expectRevert(IPoolManager.PoolAlreadyInitialized.selector);
        poolManager.initialize(key, SQRT_PRICE_1_1);
    }

    function test_Initialize_RevertWhen_AlreadyInitialized_DifferentSqrtPrice() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, 60);
        poolManager.initialize(key, SQRT_PRICE_1_1);
        uint160 otherPrice = TickMath.getSqrtPriceAtTickPublic(100);
        vm.expectRevert(IPoolManager.PoolAlreadyInitialized.selector);
        poolManager.initialize(key, otherPrice);
    }

    // ---------- Revert: invalid sqrtPrice (TickMath.getTickAtSqrtPrice) ----------

    function test_Initialize_RevertWhen_SqrtPriceBelowMin() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, 60);
        uint160 belowMin = MIN_SQRT_PRICE - 1;
        vm.expectRevert(abi.encodeWithSelector(TickMath.InvalidSqrtPrice.selector, belowMin));
        poolManager.initialize(key, belowMin);
    }

    function test_Initialize_RevertWhen_SqrtPriceZero() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, 60);
        vm.expectRevert(abi.encodeWithSelector(TickMath.InvalidSqrtPrice.selector, uint160(0)));
        poolManager.initialize(key, 0);
    }

    function test_Initialize_RevertWhen_SqrtPriceAtOrAboveMax() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, 60);
        vm.expectRevert(abi.encodeWithSelector(TickMath.InvalidSqrtPrice.selector, MAX_SQRT_PRICE));
        poolManager.initialize(key, MAX_SQRT_PRICE);
    }
}
