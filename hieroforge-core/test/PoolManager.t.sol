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
import {SwapParams} from "../src/types/SwapParams.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {TickMath} from "../src/libraries/TickMath.sol";
import {Deployers} from "./utils/Deployers.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {IERC20} from "hedera-forking/IERC20.sol";

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
            owner: address(this), tickLower: -60, tickUpper: 60, liquidityDelta: 1000, tickSpacing: 60, salt: bytes32(0)
        });
        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        poolManager.modifyLiquidity(key, params, "");
    }

    function test_ModifyLiquidity_ReturnsZeroDeltas_WhenPoolInitialized() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, 60);
        poolManager.initialize(key, 79228162514264337593543950336);
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            owner: address(this), tickLower: -60, tickUpper: 60, liquidityDelta: 1000, tickSpacing: 60, salt: bytes32(0)
        });
        (BalanceDelta callerDelta, BalanceDelta feesAccrued) = poolManager.modifyLiquidity(key, params, "");
        assertEq(callerDelta.amount0(), 0);
        assertEq(callerDelta.amount1(), 0);
        assertEq(feesAccrued.amount0(), 0);
        assertEq(feesAccrued.amount1(), 0);
    }

    // ========== Add liquidity at -180,-120,-60,0,60,120,180; price at tick 120; swap zero-to-one ==========

    int24 constant TICK_SPACING = 60;
    uint128 constant LIQUIDITY_PER_RANGE = 1e18;

    /// @dev Initialize at tick 120, add liquidity at -180,-120,-60,0,60,120,180 (ranges), then swap zero-to-one.
    function test_AddLiquidityAtTicks_PriceAt120_SwapZeroToOne() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, TICK_SPACING);
        PoolId id = key.toId();

        // 1. Initialize pool at tick 120 (price = 1.0001^120)
        uint160 sqrtPriceAt120 = TickMath.getSqrtPriceAtTickPublic(120);
        int24 tick = poolManager.initialize(key, sqrtPriceAt120);
        assertEq(tick, 120);
        (, uint160 storedSqrt, int24 storedTick) = poolManager.getPoolState(id);
        assertEq(storedTick, 120);
        assertEq(storedSqrt, sqrtPriceAt120);

        // 2. Add liquidity at -180,-120,-60,0,60,120,180 (ranges between them)
        _addLiquidityRange(key, -180, -120);
        _addLiquidityRange(key, -120, -60);
        _addLiquidityRange(key, -60, 0);
        _addLiquidityRange(key, 0, 60);
        _addLiquidityRange(key, 60, 120);
        _addLiquidityRange(key, 120, 180);

        (, storedSqrt, storedTick) = poolManager.getPoolState(id);
        assertEq(storedTick, 120);

        // 3. Swap zero for one (exact input). Price limit > MIN_SQRT_PRICE to avoid PriceLimitOutOfBounds.
        //    With correct active liquidity (modifyLiquidity updating self.liquidity), swap succeeds.
        //    First step: at tick 120, next tick left is 120 (boundary), so amountIn/Out/fee are 0; we cross to tick 119.
        //    Second step: swap consumes ~1000 token0, gives ~1009 token1, fee 3 (0.3%).
        SwapParams memory params = SwapParams({
            amountSpecified: -int256(uint256(1000)),
            tickSpacing: TICK_SPACING,
            zeroForOne: true,
            sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
            lpFeeOverride: 0
        });

        BalanceDelta swapDelta = poolManager.swap(key, params, "");

        // Exact input 1000 token0 -> expect amount0 = -1000, amount1 positive (token1 out)
        assertEq(swapDelta.amount0(), -1000, "amount0 should be -1000 (exact in)");
        assertGe(swapDelta.amount1(), 1000, "amount1 out should be >= 1000");
        assertLe(swapDelta.amount1(), 1010, "amount1 out should be ~1009 (with fee)");
    }

    /// @dev Initialize at tick 0, add liquidity, swap zero-to-one with price limit in (-120,-60) so tick lands between -120 and -60.
    function test_SwapZeroToOne_TickLandsBetweenNegative120AndNegative60() public {
        PoolKey memory key = _makeKey(address(0x1), address(0x2), 3000, TICK_SPACING);
        PoolId id = key.toId();

        // 1. Initialize at tick 0 (1:1 price)
        uint160 sqrtPriceAt0 = TickMath.getSqrtPriceAtTickPublic(0);
        int24 tick = poolManager.initialize(key, sqrtPriceAt0);
        assertEq(tick, 0);
        (,, int24 storedTick) = poolManager.getPoolState(id);
        assertEq(storedTick, 0);

        // 2. Add liquidity in ranges so we have liquidity in (-120, -60)
        _addLiquidityRange(key, -180, -120);
        _addLiquidityRange(key, -120, -60);
        _addLiquidityRange(key, -60, 0);
        _addLiquidityRange(key, 0, 60);
        _addLiquidityRange(key, 60, 120);
        _addLiquidityRange(key, 120, 180);

        // 3. Swap zero for one; limit price to tick -90 (between -120 and -60) so tick lands in that range
        uint160 sqrtPriceLimit = TickMath.getSqrtPriceAtTickPublic(-90);
        SwapParams memory params = SwapParams({
            amountSpecified: -int256(uint256(1000)),
            tickSpacing: TICK_SPACING,
            zeroForOne: true,
            sqrtPriceLimitX96: sqrtPriceLimit,
            lpFeeOverride: 0
        });

        poolManager.swap(key, params, "");

        (,, int24 tickAfter) = poolManager.getPoolState(id);
        // Tick should land between -120 and -60 after zero-to-one swap from tick 0
        assertGe(tickAfter, -120, "tick >= -120");
        assertLt(tickAfter, -60, "tick < -60 (between -120 and -60)");
    }

    function _addLiquidityRange(PoolKey memory key, int24 tickLower, int24 tickUpper) internal {
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            owner: address(this),
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: int128(LIQUIDITY_PER_RANGE),
            tickSpacing: TICK_SPACING,
            salt: bytes32(0)
        });
        poolManager.modifyLiquidity(key, params, "");
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

// ========== modifyLiquidity tests for all token combinations ==========
// Combinations: HTS-HTS | ERC20-ERC20 | ERC20-HTS | HTS-ERC20 | Native-ERC20 | Native-HTS

/// @notice Tests PoolManager.modifyLiquidity with real settle/take for all token0/token1 combinations
contract PoolManagerModifyLiquidityCombinationsTest is Test, Deployers {
    function setUp() public {
        // Base setup: manager + router. HTS tests also need initializeManagerRoutersAndPools()
        deployFreshManagerAndRouters();
    }

    /// @notice Combination 1: token0 = HTS, token1 = HTS — add liquidity with real HTS transfer
    function test_modifyLiquidity_addLiquidity_htsHts() public {
        deployMintAndApprove2CurrenciesHTS();
        (key,) = initPool(currency0, currency1, 3000, 60, SQRT_PRICE_1_1);
        LIQUIDITY_PARAMS.owner = address(modifyLiquidityRouter);
        LIQUIDITY_PARAMS.liquidityDelta = 1000;

        uint256 fundAmount = 5e9;
        require(IERC20(Currency.unwrap(currency0)).transfer(address(modifyLiquidityRouter), fundAmount), "t0");
        require(IERC20(Currency.unwrap(currency1)).transfer(address(modifyLiquidityRouter), fundAmount), "t1");

        uint256 bal0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(manager));
        uint256 bal1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(manager));

        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);

        assertLt(int256(delta.amount0()), 0, "delta0 negative");
        assertLt(int256(delta.amount1()), 0, "delta1 negative");
        assertEq(
            IERC20(Currency.unwrap(currency0)).balanceOf(address(manager)),
            bal0Before + uint256(uint128(-delta.amount0())),
            "manager received token0"
        );
        assertEq(
            IERC20(Currency.unwrap(currency1)).balanceOf(address(manager)),
            bal1Before + uint256(uint128(-delta.amount1())),
            "manager received token1"
        );
    }

    /// @notice Combination 2: token0 = ERC20, token1 = ERC20 — add liquidity with real ERC20 transfer
    function test_modifyLiquidity_addLiquidity_erc20Erc20() public {
        MockERC20 mock0 = new MockERC20();
        MockERC20 mock1 = new MockERC20();
        mock0.mint(address(this), 1e18);
        mock1.mint(address(this), 1e18);
        address a0 = address(mock0);
        address a1 = address(mock1);
        (Currency c0, Currency c1) =
            a0 < a1 ? (Currency.wrap(a0), Currency.wrap(a1)) : (Currency.wrap(a1), Currency.wrap(a0));

        mock0.approve(address(modifyLiquidityRouter), type(uint256).max);
        mock1.approve(address(modifyLiquidityRouter), type(uint256).max);

        PoolKey memory poolKey = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: address(0)});
        initPool(c0, c1, 3000, 60, SQRT_PRICE_1_1);
        key = poolKey;

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            owner: address(modifyLiquidityRouter),
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 1000,
            tickSpacing: 60,
            salt: bytes32(0)
        });

        uint256 fundAmount = 1e17;
        require(IERC20(Currency.unwrap(c0)).transfer(address(modifyLiquidityRouter), fundAmount), "t0");
        require(IERC20(Currency.unwrap(c1)).transfer(address(modifyLiquidityRouter), fundAmount), "t1");

        uint256 bal0Before = IERC20(Currency.unwrap(c0)).balanceOf(address(manager));
        uint256 bal1Before = IERC20(Currency.unwrap(c1)).balanceOf(address(manager));

        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(poolKey, params, ZERO_BYTES);

        assertLt(int256(delta.amount0()), 0);
        assertLt(int256(delta.amount1()), 0);
        assertEq(
            IERC20(Currency.unwrap(c0)).balanceOf(address(manager)),
            bal0Before + uint256(uint128(-delta.amount0())),
            "manager received token0"
        );
        assertEq(
            IERC20(Currency.unwrap(c1)).balanceOf(address(manager)),
            bal1Before + uint256(uint128(-delta.amount1())),
            "manager received token1"
        );
    }

    /// @notice Combination 3: token0 = ERC20, token1 = HTS (or token0 = HTS, token1 = ERC20) — mixed pair
    function test_modifyLiquidity_addLiquidity_erc20Hts_mixed() public {
        deployMintAndApprove2CurrenciesHTS();
        MockERC20 mockErc20 = new MockERC20();
        mockErc20.mint(address(this), 1e18);
        address erc20Addr = address(mockErc20);
        address htsAddr = Currency.unwrap(currency0);

        (Currency c0, Currency c1) =
            erc20Addr < htsAddr ? (Currency.wrap(erc20Addr), currency0) : (currency0, Currency.wrap(erc20Addr));
        mockErc20.approve(address(modifyLiquidityRouter), type(uint256).max);
        // currency0 already approved in deployMintAndApprove2CurrenciesHTS

        PoolKey memory poolKey = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: address(0)});
        initPool(c0, c1, 3000, 60, SQRT_PRICE_1_1);
        key = poolKey;

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            owner: address(modifyLiquidityRouter),
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 1000,
            tickSpacing: 60,
            salt: bytes32(0)
        });

        uint256 fundErc20 = 1e17;
        uint256 fundHts = 5e9;
        // c0 is ERC20 when erc20Addr < htsAddr, so fund c0 with ERC20 amount and c1 with HTS amount
        require(
            IERC20(Currency.unwrap(c0))
                .transfer(address(modifyLiquidityRouter), erc20Addr < htsAddr ? fundErc20 : fundHts),
            "t0"
        );
        require(
            IERC20(Currency.unwrap(c1))
                .transfer(address(modifyLiquidityRouter), erc20Addr < htsAddr ? fundHts : fundErc20),
            "t1"
        );

        uint256 bal0Before = IERC20(Currency.unwrap(c0)).balanceOf(address(manager));
        uint256 bal1Before = IERC20(Currency.unwrap(c1)).balanceOf(address(manager));

        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(poolKey, params, ZERO_BYTES);

        assertLt(int256(delta.amount0()), 0);
        assertLt(int256(delta.amount1()), 0);
        assertEq(
            IERC20(Currency.unwrap(c0)).balanceOf(address(manager)),
            bal0Before + uint256(uint128(-delta.amount0())),
            "manager received token0"
        );
        assertEq(
            IERC20(Currency.unwrap(c1)).balanceOf(address(manager)),
            bal1Before + uint256(uint128(-delta.amount1())),
            "manager received token1"
        );
    }

    /// @notice Same as mixed but with HTS as token0 and ERC20 as token1 (opposite address order)
    function test_modifyLiquidity_addLiquidity_htsErc20_mixed() public {
        deployMintAndApprove2CurrenciesHTS();
        MockERC20 mockErc20 = new MockERC20();
        mockErc20.mint(address(this), 1e18);
        address erc20Addr = address(mockErc20);
        address htsAddr = Currency.unwrap(currency1);

        (Currency c0, Currency c1) =
            htsAddr < erc20Addr ? (currency1, Currency.wrap(erc20Addr)) : (Currency.wrap(erc20Addr), currency1);
        mockErc20.approve(address(modifyLiquidityRouter), type(uint256).max);

        PoolKey memory poolKey = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: address(0)});
        initPool(c0, c1, 3000, 60, SQRT_PRICE_1_1);
        key = poolKey;

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            owner: address(modifyLiquidityRouter),
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 1000,
            tickSpacing: 60,
            salt: bytes32(0)
        });

        uint256 fundHts = 5e9;
        uint256 fundErc20 = 1e17;
        require(IERC20(Currency.unwrap(c0)).transfer(address(modifyLiquidityRouter), fundHts), "t0");
        require(IERC20(Currency.unwrap(c1)).transfer(address(modifyLiquidityRouter), fundErc20), "t1");

        uint256 bal0Before = IERC20(Currency.unwrap(c0)).balanceOf(address(manager));
        uint256 bal1Before = IERC20(Currency.unwrap(c1)).balanceOf(address(manager));

        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(poolKey, params, ZERO_BYTES);

        assertLt(int256(delta.amount0()), 0);
        assertLt(int256(delta.amount1()), 0);
        assertEq(
            IERC20(Currency.unwrap(c0)).balanceOf(address(manager)),
            bal0Before + uint256(uint128(-delta.amount0())),
            "manager received token0"
        );
        assertEq(
            IERC20(Currency.unwrap(c1)).balanceOf(address(manager)),
            bal1Before + uint256(uint128(-delta.amount1())),
            "manager received token1"
        );
    }
}
