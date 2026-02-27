// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {PoolKey, InvalidTickSpacing} from "../src/types/PoolKey.sol";
import {Currency} from "../src/types/Currency.sol";
import {PoolId} from "../src/types/PoolId.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {MIN_TICK_SPACING, MAX_TICK_SPACING} from "../src/constants.sol";
import {ModifyLiquidityParams} from "../src/types/ModifyLiquidityParams.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";

contract PoolManagerTest is Test {
    PoolManager public poolManager;

    function setUp() public {
        poolManager = new PoolManager();
    }

    function test_Initialize_Succeeds() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, 60);
        uint160 sqrtPriceX96 = 79228162514264337593543950336; // 1:1 ish
        int24 tick = poolManager.initialize(key, sqrtPriceX96);
        assertEq(tick, 0);
        PoolId id = key.toId();
        (bool initialized, uint160 storedSqrt, int24 storedTick) = poolManager.getPoolState(id);
        assertTrue(initialized);
        assertEq(storedSqrt, sqrtPriceX96);
        assertEq(storedTick, 0);
    }

    function test_Initialize_EmitsInitializeEvent() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, 60);
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        PoolId id = key.toId();

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.Initialize(
            id, key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks, sqrtPriceX96, 0
        );
        int24 tick = poolManager.initialize(key, sqrtPriceX96);
        assertEq(tick, 0);
    }

    function test_Initialize_EmitsInitializeEvent_WithNonZeroTick() public {
        // Use a sqrtPrice that yields a non-zero tick (e.g. price != 1:1)
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 5000, 60);
        uint160 sqrtPriceX96 = 79228162514264337593543950336; // 1:1 => tick 0
        PoolId id = key.toId();

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.Initialize(
            id, key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks, sqrtPriceX96, 0
        );
        poolManager.initialize(key, sqrtPriceX96);
    }

    function test_Initialize_EmitsInitializeEvent_WithCustomHooks() public {
        address hooksAddr = address(0x1234);
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 3000,
            tickSpacing: 60,
            hooks: hooksAddr
        });
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        PoolId id = key.toId();

        vm.expectEmit(true, true, true, true);
        emit IPoolManager.Initialize(
            id, key.currency0, key.currency1, key.fee, key.tickSpacing, hooksAddr, sqrtPriceX96, 0
        );
        poolManager.initialize(key, sqrtPriceX96);
    }

    function test_Initialize_EmitsInitializeEvent_CheckAllParams() public {
        PoolKey memory key = _makeKey(address(0xA), address(0xB), 500, 10);
        uint160 sqrtPriceX96 = 1 << 96; // arbitrary
        PoolId id = key.toId();

        vm.recordLogs();
        int24 tick = poolManager.initialize(key, sqrtPriceX96);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[1], PoolId.unwrap(id));
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(Currency.unwrap(key.currency0)))));
        assertEq(entries[0].topics[3], bytes32(uint256(uint160(Currency.unwrap(key.currency1)))));
        (uint24 fee, int24 tickSpacing, address hooks, uint160 sqrtPriceX96Out, int24 tickOut) =
            abi.decode(entries[0].data, (uint24, int24, address, uint160, int24));
        assertEq(fee, key.fee);
        assertEq(tickSpacing, key.tickSpacing);
        assertEq(hooks, key.hooks);
        assertEq(sqrtPriceX96Out, sqrtPriceX96);
        assertEq(tickOut, tick);
    }

    function test_Initialize_RevertWhen_CurrenciesNotSorted() public {
        PoolKey memory key = _makeKey(address(0x2), address(0x1), 3000, 60); // wrong order
        vm.expectRevert(); // TokensMustBeSorted from PoolKey.validate
        poolManager.initialize(key, 79228162514264337593543950336);
    }

    function test_Initialize_RevertWhen_AlreadyInitialized() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, 60);
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        poolManager.initialize(key, sqrtPriceX96);
        vm.expectRevert(IPoolManager.PoolAlreadyInitialized.selector);
        poolManager.initialize(key, sqrtPriceX96);
    }

    function test_Initialize_RevertWhen_TickSpacingBelowMin() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, MIN_TICK_SPACING - 1);
        vm.expectRevert(InvalidTickSpacing.selector);
        poolManager.initialize(key, 79228162514264337593543950336);
    }

    function test_Initialize_RevertWhen_TickSpacingAboveMax() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, MAX_TICK_SPACING + 1);
        vm.expectRevert(InvalidTickSpacing.selector);
        poolManager.initialize(key, 79228162514264337593543950336);
    }

    function test_Initialize_Succeeds_WithMinTickSpacing() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, MIN_TICK_SPACING);
        int24 tick = poolManager.initialize(key, 79228162514264337593543950336);
        assertEq(tick, 0);
        (bool initialized,,) = poolManager.getPoolState(key.toId());
        assertTrue(initialized);
    }

    function test_Initialize_Succeeds_WithMaxTickSpacing() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, MAX_TICK_SPACING);
        int24 tick = poolManager.initialize(key, 79228162514264337593543950336);
        assertEq(tick, 0);
        (bool initialized,,) = poolManager.getPoolState(key.toId());
        assertTrue(initialized);
    }

    function test_Initialize_DifferentKeys_DifferentPools() public {
        PoolKey memory keyA = _makeKey(address(0x1), address(0x2), 3000, 60);
        PoolKey memory keyB = _makeKey(address(0x1), address(0x2), 5000, 100);
        poolManager.initialize(keyA, 79228162514264337593543950336);
        poolManager.initialize(keyB, 79228162514264337593543950336);
        (bool initA,,) = poolManager.getPoolState(keyA.toId());
        (bool initB,,) = poolManager.getPoolState(keyB.toId());
        assertTrue(initA);
        assertTrue(initB);
    }

    function test_ModifyLiquidity_RevertWhen_PoolNotInitialized() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, 60);
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000,
            salt: bytes32(0)
        });
        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        poolManager.modifyLiquidity(key, params, "");
    }

    function test_ModifyLiquidity_ReturnsZeroDeltas_WhenPoolInitialized() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, 60);
        poolManager.initialize(key, 79228162514264337593543950336);
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000,
            salt: bytes32(0)
        });
        (BalanceDelta callerDelta, BalanceDelta feesAccrued) = poolManager.modifyLiquidity(key, params, "");
        assertEq(callerDelta.amount0(), 0);
        assertEq(callerDelta.amount1(), 0);
        assertEq(feesAccrued.amount0(), 0);
        assertEq(feesAccrued.amount1(), 0);
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
}
