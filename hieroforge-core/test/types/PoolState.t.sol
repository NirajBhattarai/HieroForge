// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PoolState, checkPoolInitialized, modifyLiquidity, getLiquidity} from "../../src/types/PoolState.sol";
import {initialSlot0} from "../../src/types/Slot0.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {ModifyLiquidityParams} from "../../src/types/ModifyLiquidityParams.sol";
import {ModifyLiquidityOperation} from "../../src/types/PoolOperation.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";

// TickMath bounds (same as TickMath.sol) for boundary tests
uint160 constant MIN_SQRT_PRICE = 4295128739;
uint160 constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;

/// @notice Helper to call PoolState free functions so we can test them directly
contract PoolStateCheckHelper {
    PoolState state;

    function setSlot0Initialized(uint160 sqrtPriceX96) external {
        (state.slot0,) = initialSlot0(sqrtPriceX96, 3000);
    }

    function setLiquidity(uint128 liquidity) external {
        state.liquidity = liquidity;
    }

    function checkPoolInitializedExternal() external view {
        checkPoolInitialized(state);
    }

    function getLiquidityExternal() external view returns (uint128) {
        return getLiquidity(state);
    }

    function modifyLiquidityExternal(
        ModifyLiquidityParams memory params,
        address owner,
        int24 tickSpacing,
        bytes calldata hookData
    ) external returns (BalanceDelta callerDelta, BalanceDelta feesAccrued) {
        ModifyLiquidityOperation memory op = ModifyLiquidityOperation({
            owner: owner,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidityDelta: int128(params.liquidityDelta),
            tickSpacing: tickSpacing,
            salt: params.salt
        });
        return modifyLiquidity(state, op, hookData);
    }
}

contract PoolStateTest is Test {
    PoolStateCheckHelper public helper;

    function setUp() public {
        helper = new PoolStateCheckHelper();
    }

    // ========== checkPoolInitialized: not initialized ==========

    function test_CheckPoolInitialized_RevertsWhen_NotInitialized() public {
        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        helper.checkPoolInitializedExternal();
    }

    function test_CheckPoolInitialized_RevertSelector_IsPoolNotInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(IPoolManager.PoolNotInitialized.selector));
        helper.checkPoolInitializedExternal();
    }

    // ========== checkPoolInitialized: initialized (no revert) ==========

    function test_CheckPoolInitialized_DoesNotRevert_WhenInitialized() public {
        uint160 sqrtPriceX96 = 79228162514264337593543950336; // 1:1 ish
        helper.setSlot0Initialized(sqrtPriceX96);
        helper.checkPoolInitializedExternal(); // should not revert
    }

    function test_CheckPoolInitialized_DoesNotRevert_WhenInitialized_NonZeroTick() public {
        uint160 sqrtPriceX96 = 1 << 96; // arbitrary price
        helper.setSlot0Initialized(sqrtPriceX96);
        helper.checkPoolInitializedExternal(); // should not revert
    }

    /// @dev Smallest valid sqrtPriceX96 for initialSlot0 (TickMath lower bound)
    function test_CheckPoolInitialized_DoesNotRevert_AtMinSqrtPrice() public {
        helper.setSlot0Initialized(MIN_SQRT_PRICE);
        helper.checkPoolInitializedExternal();
    }

    /// @dev Just below TickMath upper bound (getTickAtSqrtPrice valid range is [MIN_SQRT_PRICE, MAX_SQRT_PRICE) )
    function test_CheckPoolInitialized_DoesNotRevert_JustBelowMaxSqrtPrice() public {
        helper.setSlot0Initialized(MAX_SQRT_PRICE - 1);
        helper.checkPoolInitializedExternal();
    }

    function test_CheckPoolInitialized_DoesNotRevert_WhenCalledMultipleTimes() public {
        helper.setSlot0Initialized(79228162514264337593543950336);
        helper.checkPoolInitializedExternal();
        helper.checkPoolInitializedExternal();
        helper.checkPoolInitializedExternal();
    }

    /// @dev After slot0 is overwritten with another valid price, check still passes
    function test_CheckPoolInitialized_DoesNotRevert_AfterSlot0Overwritten() public {
        helper.setSlot0Initialized(79228162514264337593543950336);
        helper.checkPoolInitializedExternal();
        helper.setSlot0Initialized(1 << 96);
        helper.checkPoolInitializedExternal();
    }

    // ========== modifyLiquidity (uses checkPoolInitialized) ==========

    function test_ModifyLiquidity_RevertsWhen_NotInitialized() public {
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 1000, salt: bytes32(0)});
        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        helper.modifyLiquidityExternal(params, address(this), 60, "");
    }

    function test_ModifyLiquidity_DoesNotRevert_WhenInitialized() public {
        helper.setSlot0Initialized(79228162514264337593543950336);
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 0, salt: bytes32(0)});
        (BalanceDelta callerDelta, BalanceDelta feesAccrued) =
            helper.modifyLiquidityExternal(params, address(this), 60, "");
        assertEq(callerDelta.amount0(), 0);
        assertEq(callerDelta.amount1(), 0);
        assertEq(feesAccrued.amount0(), 0);
        assertEq(feesAccrued.amount1(), 0);
    }

    function test_ModifyLiquidity_WithNonEmptyHookData_DoesNotRevert() public {
        helper.setSlot0Initialized(79228162514264337593543950336);
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 0,
            salt: keccak256("salt")
        });
        helper.modifyLiquidityExternal(params, address(0x1), 60, "hook data");
    }

    function test_ModifyLiquidity_WithZeroLiquidityDelta_DoesNotRevert() public {
        helper.setSlot0Initialized(79228162514264337593543950336);
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 0, salt: bytes32(0)});
        helper.modifyLiquidityExternal(params, address(this), 60, "");
    }

    // ========== getLiquidity ==========

    function test_GetLiquidity_ReturnsZero_ByDefault() public view {
        assertEq(helper.getLiquidityExternal(), 0);
    }

    function test_GetLiquidity_ReturnsSetValue() public {
        helper.setLiquidity(1);
        assertEq(helper.getLiquidityExternal(), 1);
    }

    function test_GetLiquidity_ReturnsSetValue_WhenInitialized() public {
        helper.setSlot0Initialized(79228162514264337593543950336);
        helper.setLiquidity(1e18);
        assertEq(helper.getLiquidityExternal(), 1e18);
    }

    function test_GetLiquidity_ReturnsMaxUint128_WhenSet() public {
        helper.setLiquidity(type(uint128).max);
        assertEq(helper.getLiquidityExternal(), type(uint128).max);
    }
}
