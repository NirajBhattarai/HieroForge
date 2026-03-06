// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {PoolId} from "../src/types/PoolId.sol";
import {Currency} from "../src/types/Currency.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "../src/types/ModifyLiquidityParams.sol";
import {SwapParams} from "../src/types/SwapParams.sol";
import {TickMath} from "../src/libraries/TickMath.sol";
import {Deployers} from "./utils/Deployers.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {IERC20} from "hedera-forking/IERC20.sol";
import {IUnlockCallback} from "../src/callback/IUnlockCallback.sol";

/// @notice Tests for PoolManager.swap with delta accounting (Uniswap v4-style).
/// Swap delta is accounted to msg.sender; caller must settle/take inside unlock or subsequent unlock.
contract PoolManagerSwapTest is Test, Deployers {
    int24 constant TICK_SPACING = 60;
    uint128 constant LIQUIDITY_PER_RANGE = 1e18;

    function setUp() public {
        deployFreshManagerAndRouters();
    }

    /// @notice Full swap flow: init pool, add liquidity with ERC20s, swap zero-for-one via Router, assert delta and balances.
    function test_swap_viaRouter_zeroForOne_exactInput() public {
        (PoolKey memory key, PoolId id) = _setupPoolWithLiquidity();

        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        uint256 amountIn = 1000;
        IERC20(token0).transfer(address(modifyLiquidityRouter), amountIn);

        uint256 bal0ManagerBefore = IERC20(token0).balanceOf(address(manager));
        uint256 bal1ManagerBefore = IERC20(token1).balanceOf(address(manager));
        uint256 bal1CallerBefore = IERC20(token1).balanceOf(address(this));

        SwapParams memory params = SwapParams({
            amountSpecified: -int256(amountIn),
            tickSpacing: TICK_SPACING,
            zeroForOne: true,
            sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
            lpFeeOverride: 0
        });

        BalanceDelta delta = modifyLiquidityRouter.swap(key, params, "");

        // Exact input: amount0 in = -amountIn, amount1 out positive (after ~0.3% fee, out < in)
        assertEq(delta.amount0(), -int128(int256(amountIn)), "amount0 should be -amountIn");
        assertGe(delta.amount1(), int128(int256(amountIn * 99 / 100)), "amount1 out >= amountIn minus fee");
        assertLe(delta.amount1(), int128(int256(amountIn + 15)), "amount1 out ~amountIn (with fee)");

        // Manager received token0, sent token1
        assertEq(IERC20(token0).balanceOf(address(manager)), bal0ManagerBefore + amountIn, "manager received token0");
        assertEq(
            IERC20(token1).balanceOf(address(manager)),
            bal1ManagerBefore - uint256(uint128(delta.amount1())),
            "manager sent token1"
        );
        assertEq(
            IERC20(token1).balanceOf(address(this)),
            bal1CallerBefore + uint256(uint128(delta.amount1())),
            "caller received token1"
        );
    }

    /// @notice Full swap flow: one-for-zero exact input via Router.
    function test_swap_viaRouter_oneForZero_exactInput() public {
        (PoolKey memory key, PoolId id) = _setupPoolWithLiquidity();

        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        uint256 amountIn = 1000;
        IERC20(token1).transfer(address(modifyLiquidityRouter), amountIn);

        uint256 bal0ManagerBefore = IERC20(token0).balanceOf(address(manager));
        uint256 bal1ManagerBefore = IERC20(token1).balanceOf(address(manager));
        uint256 bal0CallerBefore = IERC20(token0).balanceOf(address(this));

        SwapParams memory params = SwapParams({
            amountSpecified: -int256(amountIn),
            tickSpacing: TICK_SPACING,
            zeroForOne: false,
            sqrtPriceLimitX96: TickMath.maxSqrtPrice() - 1,
            lpFeeOverride: 0
        });

        BalanceDelta delta = modifyLiquidityRouter.swap(key, params, "");

        assertEq(delta.amount1(), -int128(int256(amountIn)), "amount1 should be -amountIn");
        assertGe(delta.amount0(), int128(int256(amountIn * 99 / 100)), "amount0 out >= amountIn minus fee");

        assertEq(IERC20(token1).balanceOf(address(manager)), bal1ManagerBefore + amountIn, "manager received token1");
        assertEq(
            IERC20(token0).balanceOf(address(this)),
            bal0CallerBefore + uint256(uint128(delta.amount0())),
            "caller received token0"
        );
    }

    /// @notice If swap is called inside unlock but deltas are not settled, unlock reverts with CurrencyNotSettled.
    function test_swap_revertWhen_deltaNotSettled() public {
        (PoolKey memory key,) = _setupPoolWithLiquidity();
        uint256 amountIn = 100;
        SwapParams memory params = SwapParams({
            amountSpecified: -int256(amountIn),
            tickSpacing: TICK_SPACING,
            zeroForOne: true,
            sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
            lpFeeOverride: 0
        });

        NoSettleSwapRouter noSettleRouter = new NoSettleSwapRouter(manager);
        vm.expectRevert(IPoolManager.CurrencyNotSettled.selector);
        noSettleRouter.doUnlock(key, params);
    }

    /// @notice Swap with zero amountSpecified reverts.
    function test_swap_revertWhen_amountSpecifiedZero() public {
        (PoolKey memory key,) = _setupPoolWithLiquidity();
        SwapParams memory params = SwapParams({
            amountSpecified: 0,
            tickSpacing: TICK_SPACING,
            zeroForOne: true,
            sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
            lpFeeOverride: 0
        });
        vm.expectRevert(IPoolManager.SwapAmountCannotBeZero.selector);
        modifyLiquidityRouter.swap(key, params, "");
    }

    /// @notice Swap on uninitialized pool reverts.
    function test_swap_revertWhen_poolNotInitialized() public {
        deployFreshManagerAndRouters();
        MockERC20 t0 = new MockERC20();
        MockERC20 t1 = new MockERC20();
        t0.mint(address(this), 1e18);
        t1.mint(address(this), 1e18);
        (Currency c0, Currency c1) = _sortCurrencies(address(t0), address(t1));
        PoolKey memory key =
            PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: TICK_SPACING, hooks: address(0)});
        // Do not initialize
        SwapParams memory params = SwapParams({
            amountSpecified: -int256(1000),
            tickSpacing: TICK_SPACING,
            zeroForOne: true,
            sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
            lpFeeOverride: 0
        });
        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        modifyLiquidityRouter.swap(key, params, "");
    }

    // ---- Helpers ----

    function _setupPoolWithLiquidity() internal returns (PoolKey memory key, PoolId id) {
        MockERC20 mock0 = new MockERC20();
        MockERC20 mock1 = new MockERC20();
        mock0.mint(address(this), 1e18);
        mock1.mint(address(this), 1e18);
        (Currency c0, Currency c1) = _sortCurrencies(address(mock0), address(mock1));
        key = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: TICK_SPACING, hooks: address(0)});
        (key, id) = initPool(c0, c1, 3000, TICK_SPACING, SQRT_PRICE_1_1);

        LIQUIDITY_PARAMS.owner = address(modifyLiquidityRouter);
        LIQUIDITY_PARAMS.liquidityDelta = int128(LIQUIDITY_PER_RANGE);
        LIQUIDITY_PARAMS.tickLower = -180;
        LIQUIDITY_PARAMS.tickUpper = 180;
        LIQUIDITY_PARAMS.tickSpacing = TICK_SPACING;
        mock0.approve(address(modifyLiquidityRouter), type(uint256).max);
        mock1.approve(address(modifyLiquidityRouter), type(uint256).max);
        IERC20(Currency.unwrap(c0)).transfer(address(modifyLiquidityRouter), 1e17);
        IERC20(Currency.unwrap(c1)).transfer(address(modifyLiquidityRouter), 1e17);
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, "");

        // Fund router with both tokens for swaps
        IERC20(Currency.unwrap(c0)).transfer(address(modifyLiquidityRouter), 1e17);
        IERC20(Currency.unwrap(c1)).transfer(address(modifyLiquidityRouter), 1e17);
    }

    function _sortCurrencies(address a, address b) internal pure returns (Currency c0, Currency c1) {
        if (a < b) return (Currency.wrap(a), Currency.wrap(b));
        return (Currency.wrap(b), Currency.wrap(a));
    }
}

/// @notice Router that swaps in unlock callback but does NOT settle/take (used to test CurrencyNotSettled revert).
contract NoSettleSwapRouter is IUnlockCallback {
    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    struct CallbackData {
        PoolKey key;
        SwapParams params;
        bytes hookData;
    }

    function doUnlock(PoolKey memory key, SwapParams memory params) external {
        manager.unlock(abi.encode(CallbackData({key: key, params: params, hookData: ""})));
    }

    function unlockCallback(bytes calldata rawData) external override returns (bytes memory) {
        require(msg.sender == address(manager));
        CallbackData memory data = abi.decode(rawData, (CallbackData));
        BalanceDelta delta = manager.swap(data.key, data.params, data.hookData);
        // Intentionally do not settle or take - delta remains, unlock will revert
        return abi.encode(delta);
    }
}
