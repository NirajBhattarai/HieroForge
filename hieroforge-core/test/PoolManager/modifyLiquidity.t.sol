// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {PoolManager} from "../../src/PoolManager.sol";
import {PoolKey, TokensMustBeSorted, InvalidTickSpacing} from "../../src/types/PoolKey.sol";
import {PoolId} from "../../src/types/PoolId.sol";
import {MIN_TICK_SPACING, MAX_TICK_SPACING, MIN_TICK, MAX_TICK} from "../../src/constants.sol";
import {ModifyLiquidityParams} from "../../src/types/ModifyLiquidityParams.sol";
import {
    TickMisaligned,
    TicksMisordered,
    TickLowerOutOfBounds,
    TickUpperOutOfBounds,
    TickLiquidityOverflow
} from "../../src/types/PoolState.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";
import {TickMath} from "../../src/libraries/TickMath.sol";
import {Currency} from "../../src/types/Currency.sol";
import {Deployers} from "../utils/Deployers.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import {IERC20} from "hedera-forking/IERC20.sol";

/// @notice Tests for PoolManager.modifyLiquidity (Uniswap v4-style setup).
/// @dev On Hedera, the native token (HBAR) is HTS-native (tokenized at consensus), so we treat token types as HTS and ERC20.
///   Hedera combinations (2^2 - 1 invalid = 3 valid pairs): HTS-HTS, ERC20-ERC20, HTS-ERC20 (and ERC20-HTS by address order).
///   We also test EVM-native (address(0)) for cross-chain: Native-ERC20, Native-HTS, Native-Native (reverts).
///   Total: 1. HTS-HTS  2. ERC20-ERC20  3. ERC20-HTS  4. HTS-ERC20  5. Native-ERC20  6. Native-HTS  7. Native-Native (reverts)
contract PoolManagerModifyLiquidityTest is Test, Deployers {
    /// @notice Default initial sqrt price for the pool; set in a test then call initializeManagerRoutersAndPools() to re-init with it.
    uint160 public initialSqrtPriceX96 = SQRT_PRICE_1_1;

    function getInitialSqrtPriceX96() internal view override returns (uint160) {
        return initialSqrtPriceX96;
    }

    /// @notice Option A: set custom sqrt price and re-init pool (deploy manager, currencies, init at given price). Use in tests that need a non-1:1 price.
    function reinitPoolWithSqrtPrice(uint160 sqrtPriceX96) internal {
        initialSqrtPriceX96 = sqrtPriceX96;
        initializeManagerRoutersAndPools();
    }

    function setUp() public {
        // HTS tokens via hedera-forking at 0x167. On Hedera, native (HBAR) is HTS-native. Run with --ffi
        initializeManagerRoutersAndPools();
    }

    /// @notice First test: modifyLiquidity reverts when called directly (manager is locked)
    /// @dev In v4, modifyLiquidity may only be called from within the unlock callback
    function test_modifyLiquidity_revertsWhenLocked() public {
        vm.expectRevert(IPoolManager.ManagerLocked.selector);
        manager.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    /// @notice modifyLiquidity reverts when pool is not initialized
    /// @dev Covers PoolState.sol:330 — state.modifyLiquidity() calls checkPoolInitialized(self); uninitializedKey's pool has sqrtPriceX96 == 0 so it reverts with PoolNotInitialized
    function test_modifyLiquidity_revertsWhenPoolNotInitialized() public {
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -120, tickUpper: 120, liquidityDelta: int256(uint256(1e18)), salt: bytes32(0)
        });

        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        modifyLiquidityRouter.modifyLiquidity(uninitializedKey, params, ZERO_BYTES);
    }

    /// @notice modifyLiquidity reverts when key has unsorted currencies (key.validate() at line 67)
    function test_modifyLiquidity_revertsWhenKey_unsortedCurrencies() public {
        PoolKey memory badKey = PoolKey({
            currency0: currency1, currency1: currency0, fee: key.fee, tickSpacing: key.tickSpacing, hooks: key.hooks
        });
        vm.expectRevert(TokensMustBeSorted.selector);
        modifyLiquidityRouter.modifyLiquidity(badKey, LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    /// @notice modifyLiquidity reverts when key has invalid tickSpacing (key.validate() at line 67)
    function test_modifyLiquidity_revertsWhenKey_invalidTickSpacing() public {
        PoolKey memory badKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: key.fee,
            tickSpacing: MIN_TICK_SPACING - 1,
            hooks: key.hooks
        });
        vm.expectRevert(InvalidTickSpacing.selector);
        modifyLiquidityRouter.modifyLiquidity(badKey, LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    // ========== checkTicks: tick order, bounds, alignment ==========

    /// @notice modifyLiquidity reverts when tickLower >= tickUpper (TicksMisordered)
    function test_modifyLiquidity_revertsWhen_ticksMisordered() public {
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: 60, tickUpper: 0, liquidityDelta: int256(uint256(1e18)), salt: bytes32(0)
        });
        vm.expectRevert(abi.encodeWithSelector(TicksMisordered.selector, int24(60), int24(0)));
        modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);
    }

    /// @notice modifyLiquidity reverts when tickLower < MIN_TICK (TickLowerOutOfBounds)
    function test_modifyLiquidity_revertsWhen_tickLowerOutOfBounds() public {
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: MIN_TICK - 1, tickUpper: 120, liquidityDelta: int256(uint256(1e18)), salt: bytes32(0)
        });
        vm.expectRevert(abi.encodeWithSelector(TickLowerOutOfBounds.selector, MIN_TICK - 1));
        modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);
    }

    /// @notice modifyLiquidity reverts when tickUpper > MAX_TICK (TickUpperOutOfBounds)
    function test_modifyLiquidity_revertsWhen_tickUpperOutOfBounds() public {
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -120, tickUpper: MAX_TICK + 1, liquidityDelta: int256(uint256(1e18)), salt: bytes32(0)
        });
        vm.expectRevert(abi.encodeWithSelector(TickUpperOutOfBounds.selector, MAX_TICK + 1));
        modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);
    }

    /// @notice modifyLiquidity reverts when tickLower is not a multiple of tickSpacing (TickMisaligned)
    function test_modifyLiquidity_revertsWhen_tickMisaligned_lower() public {
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -119, // 60 * -2 = -120; -119 is misaligned for tickSpacing 60
            tickUpper: 120,
            liquidityDelta: int256(uint256(1e18)),
            salt: bytes32(0)
        });
        vm.expectRevert(abi.encodeWithSelector(TickMisaligned.selector, int24(-119), int24(60)));
        modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);
    }

    /// @notice modifyLiquidity reverts when tickUpper is not a multiple of tickSpacing (TickMisaligned)
    function test_modifyLiquidity_revertsWhen_tickMisaligned_upper() public {
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 121, // 60 * 2 = 120; 121 is misaligned for tickSpacing 60
            liquidityDelta: int256(uint256(1e18)),
            salt: bytes32(0)
        });
        vm.expectRevert(abi.encodeWithSelector(TickMisaligned.selector, int24(121), int24(60)));
        modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);
    }

    // ========== Hedera: HTS-HTS (on Hedera, native HBAR is HTS-native; two HTS tokens) ==========

    /// @notice Add liquidity: token0 = HTS, token1 = HTS. On Hedera this covers HTS-HTS and effectively native-HTS pairs.
    function test_addLiquidity_htsHts_succeedsWithTransfer() public {
        // HTS tokens (initialTotalSupply 10e9 raw units). On Hedera, native is HTS so HTS-HTS includes native-like pairs.
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 1000, // small L so token amounts are small
            salt: bytes32(0)
        });

        // Router must hold tokens to settle; this contract is the HTS treasury so we fund the router
        uint256 fundAmount = 5e9; // half of 10e9 initial supply per token
        require(IERC20(Currency.unwrap(currency0)).transfer(address(modifyLiquidityRouter), fundAmount), "transfer0");
        require(IERC20(Currency.unwrap(currency1)).transfer(address(modifyLiquidityRouter), fundAmount), "transfer1");

        uint256 managerBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(manager));
        uint256 managerBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(manager));

        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);

        // Adding liquidity: we pay both tokens (negative deltas)
        assertLt(int256(delta.amount0()), 0, "delta0 should be negative (paid token0)");
        assertLt(int256(delta.amount1()), 0, "delta1 should be negative (paid token1)");

        uint256 paid0 = uint256(uint128(-delta.amount0()));
        uint256 paid1 = uint256(uint128(-delta.amount1()));

        assertEq(
            IERC20(Currency.unwrap(currency0)).balanceOf(address(manager)),
            managerBalance0Before + paid0,
            "manager should have received token0"
        );
        assertEq(
            IERC20(Currency.unwrap(currency1)).balanceOf(address(manager)),
            managerBalance1Before + paid1,
            "manager should have received token1"
        );

        // Pool remains initialized at same price (no swap)
        PoolId id = key.toId();
        (, uint160 sqrtPriceX96, int24 tick) = PoolManager(address(manager)).getPoolState(id);
        assertEq(sqrtPriceX96, SQRT_PRICE_1_1, "pool price unchanged");
        assertEq(tick, 0, "pool tick unchanged");
    }

    // ========== Hedera: ERC20-ERC20 ==========

    /// @notice Add liquidity with token0 = ERC20, token1 = ERC20 (real ERC20 transfer to manager)
    function test_addLiquidity_erc20Erc20_succeedsWithTransfer() public {
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

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000, salt: bytes32(0)});
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

    // ========== Hedera: ERC20-HTS mixed (both orderings by address) ==========

    /// @notice Add liquidity with token0 = ERC20, token1 = HTS when ERC20 address < HTS address. On Hedera, native is HTS so this is ERC20 vs HTS (or native).
    function test_addLiquidity_erc20Hts_mixed_succeedsWithTransfer() public {
        MockERC20 mockErc20 = new MockERC20();
        mockErc20.mint(address(this), 1e18);
        address erc20Addr = address(mockErc20);
        address htsAddr = Currency.unwrap(currency0);
        (Currency c0, Currency c1) =
            erc20Addr < htsAddr ? (Currency.wrap(erc20Addr), currency0) : (currency0, Currency.wrap(erc20Addr));
        mockErc20.approve(address(modifyLiquidityRouter), type(uint256).max);

        PoolKey memory poolKey = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: address(0)});
        initPool(c0, c1, 3000, 60, SQRT_PRICE_1_1);

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000, salt: bytes32(0)});
        uint256 fundErc20 = 1e17;
        uint256 fundHts = 5e9;
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

    /// @notice Add liquidity with token0 = HTS, token1 = ERC20 when HTS address < ERC20 address. On Hedera, native is HTS so this covers native-ERC20.
    function test_addLiquidity_htsErc20_mixed_succeedsWithTransfer() public {
        MockERC20 mockErc20 = new MockERC20();
        mockErc20.mint(address(this), 1e18);
        address erc20Addr = address(mockErc20);
        address htsAddr = Currency.unwrap(currency1);
        (Currency c0, Currency c1) =
            htsAddr < erc20Addr ? (currency1, Currency.wrap(erc20Addr)) : (Currency.wrap(erc20Addr), currency1);
        mockErc20.approve(address(modifyLiquidityRouter), type(uint256).max);

        PoolKey memory poolKey = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: address(0)});
        initPool(c0, c1, 3000, 60, SQRT_PRICE_1_1);

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000, salt: bytes32(0)});
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

    // ========== EVM-native (address(0)); on Hedera native is HTS so use HTS-ERC20 / HTS-HTS for native pairs ==========

    /// @notice Add liquidity with token0 = EVM-native (address(0)), token1 = ERC20. On Hedera, native is HTS — use HTS-ERC20 test instead.
    function test_addLiquidity_nativeErc20_succeedsWithTransfer() public {
        MockERC20 mock = new MockERC20();
        mock.mint(address(this), 1e18);
        mock.approve(address(modifyLiquidityRouter), type(uint256).max);
        Currency native = Currency.wrap(address(0));
        Currency c1 = Currency.wrap(address(mock));
        PoolKey memory poolKey =
            PoolKey({currency0: native, currency1: c1, fee: 3000, tickSpacing: 60, hooks: address(0)});
        initPool(native, c1, 3000, 60, SQRT_PRICE_1_1);

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000, salt: bytes32(0)});
        uint256 fundErc20 = 1e17;
        require(IERC20(Currency.unwrap(c1)).transfer(address(modifyLiquidityRouter), fundErc20), "t1");
        vm.deal(address(modifyLiquidityRouter), 1 ether); // router uses this for settle{value: ...}

        uint256 managerEthBefore = address(manager).balance;
        uint256 managerErc20Before = IERC20(Currency.unwrap(c1)).balanceOf(address(manager));

        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(poolKey, params, ZERO_BYTES);

        assertLt(int256(delta.amount0()), 0);
        assertLt(int256(delta.amount1()), 0);
        assertEq(
            address(manager).balance, managerEthBefore + uint256(uint128(-delta.amount0())), "manager received native"
        );
        assertEq(
            IERC20(Currency.unwrap(c1)).balanceOf(address(manager)),
            managerErc20Before + uint256(uint128(-delta.amount1())),
            "manager received token1"
        );
    }

    /// @notice Add liquidity with token0 = EVM-native (address(0)), token1 = HTS. On Hedera, native is HTS so HTS-HTS covers native-HTS.
    function test_addLiquidity_nativeHts_succeedsWithTransfer() public {
        Currency native = Currency.wrap(address(0));
        Currency c1 = currency0; // one HTS
        PoolKey memory poolKey =
            PoolKey({currency0: native, currency1: c1, fee: 3000, tickSpacing: 60, hooks: address(0)});
        initPool(native, c1, 3000, 60, SQRT_PRICE_1_1);

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000, salt: bytes32(0)});
        uint256 fundHts = 5e9;
        require(IERC20(Currency.unwrap(c1)).transfer(address(modifyLiquidityRouter), fundHts), "t1");
        vm.deal(address(modifyLiquidityRouter), 1 ether); // router uses this for settle{value: ...}

        uint256 managerEthBefore = address(manager).balance;
        uint256 managerHtsBefore = IERC20(Currency.unwrap(c1)).balanceOf(address(manager));

        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(poolKey, params, ZERO_BYTES);

        assertLt(int256(delta.amount0()), 0);
        assertLt(int256(delta.amount1()), 0);
        assertEq(
            address(manager).balance, managerEthBefore + uint256(uint128(-delta.amount0())), "manager received native"
        );
        assertEq(
            IERC20(Currency.unwrap(c1)).balanceOf(address(manager)),
            managerHtsBefore + uint256(uint128(-delta.amount1())),
            "manager received token1"
        );
    }

    /// @notice Reverts when both currencies are EVM-native (address(0)). On Hedera, native is HTS so this case does not apply.
    function test_addLiquidity_nativeNative_revertsWithTokensMustBeSorted() public {
        PoolKey memory badKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(0)),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        vm.expectRevert(TokensMustBeSorted.selector);
        modifyLiquidityRouter.modifyLiquidity(badKey, LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    // ========== ModifyLiquidity behavior and edge cases ==========

    /// @notice Zero liquidity delta: no token movement, zero principal and zero fee delta
    function test_modifyLiquidity_zeroLiquidityDelta_returnsZeroDeltasAndNoTransfer() public {
        uint256 bal0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(modifyLiquidityRouter));
        uint256 bal1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(modifyLiquidityRouter));

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 0, salt: bytes32(0)});
        (BalanceDelta callerDelta, BalanceDelta feeDelta) =
            modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);

        assertEq(callerDelta.amount0(), 0, "amount0 should be 0");
        assertEq(callerDelta.amount1(), 0, "amount1 should be 0");
        assertEq(feeDelta.amount0(), 0, "fee0 should be 0");
        assertEq(feeDelta.amount1(), 0, "fee1 should be 0");
        assertEq(
            IERC20(Currency.unwrap(currency0)).balanceOf(address(modifyLiquidityRouter)),
            bal0Before,
            "router token0 balance unchanged"
        );
        assertEq(
            IERC20(Currency.unwrap(currency1)).balanceOf(address(modifyLiquidityRouter)),
            bal1Before,
            "router token1 balance unchanged"
        );
    }

    /// @notice Add liquidity then remove same amount: round-trip; second call receives tokens back
    function test_modifyLiquidity_addThenRemoveSameAmount_roundTrip() public {
        uint256 fundAmount = 5e9;
        require(IERC20(Currency.unwrap(currency0)).transfer(address(modifyLiquidityRouter), fundAmount), "t0");
        require(IERC20(Currency.unwrap(currency1)).transfer(address(modifyLiquidityRouter), fundAmount), "t1");

        int256 L = 2000;
        ModifyLiquidityParams memory addParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: L, salt: bytes32(0)});
        (BalanceDelta addDelta,) = modifyLiquidityRouter.modifyLiquidity(key, addParams, ZERO_BYTES);
        assertLt(int256(addDelta.amount0()), 0, "add: pay token0");
        assertLt(int256(addDelta.amount1()), 0, "add: pay token1");

        uint256 routerBal0AfterAdd = IERC20(Currency.unwrap(currency0)).balanceOf(address(modifyLiquidityRouter));
        uint256 routerBal1AfterAdd = IERC20(Currency.unwrap(currency1)).balanceOf(address(modifyLiquidityRouter));

        ModifyLiquidityParams memory removeParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: -L, salt: bytes32(0)});
        (BalanceDelta removeDelta,) = modifyLiquidityRouter.modifyLiquidity(key, removeParams, ZERO_BYTES);
        assertGt(int256(removeDelta.amount0()), 0, "remove: receive token0");
        assertGt(int256(removeDelta.amount1()), 0, "remove: receive token1");

        // Round-trip: router received tokens back; allow rounding (e.g. from fee/sqrt math)
        uint256 routerBal0After = IERC20(Currency.unwrap(currency0)).balanceOf(address(modifyLiquidityRouter));
        uint256 routerBal1After = IERC20(Currency.unwrap(currency1)).balanceOf(address(modifyLiquidityRouter));
        assertApproxEqAbs(
            routerBal0After,
            routerBal0AfterAdd + uint256(uint128(removeDelta.amount0())),
            20,
            "router token0 after remove"
        );
        assertApproxEqAbs(
            routerBal1After,
            routerBal1AfterAdd + uint256(uint128(removeDelta.amount1())),
            20,
            "router token1 after remove"
        );
    }

    /// @notice Position entirely below current tick: only token0 (amount1 == 0). Current tick < tickLower.
    function test_modifyLiquidity_positionBelowCurrentTick_onlyToken0() public {
        int24 tickCurrent = -240; // below range [-120, 120]
        uint160 sqrtPrice = TickMath.getSqrtPriceAtTickPublic(tickCurrent);
        (PoolKey memory poolKey,) = initPool(currency0, currency1, 100, 60, sqrtPrice);
        uint256 fundAmount = 5e9;
        require(IERC20(Currency.unwrap(currency0)).transfer(address(modifyLiquidityRouter), fundAmount), "t0");
        require(IERC20(Currency.unwrap(currency1)).transfer(address(modifyLiquidityRouter), fundAmount), "t1");

        // Current tick -240; range [-120, 120] is entirely above current tick -> only token0
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000, salt: bytes32(0)});
        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(poolKey, params, ZERO_BYTES);

        assertLt(int256(delta.amount0()), 0, "should pay token0");
        assertEq(delta.amount1(), 0, "should not pay token1");
    }

    /// @notice Position entirely above current tick: only token1 (amount0 == 0). Current tick >= tickUpper.
    function test_modifyLiquidity_positionAboveCurrentTick_onlyToken1() public {
        int24 tickCurrent = 120; // above range [-120, 0]
        uint160 sqrtPrice = TickMath.getSqrtPriceAtTickPublic(tickCurrent);
        (PoolKey memory poolKey,) = initPool(currency0, currency1, 500, 60, sqrtPrice);
        uint256 fundAmount = 5e9;
        require(IERC20(Currency.unwrap(currency0)).transfer(address(modifyLiquidityRouter), fundAmount), "t0");
        require(IERC20(Currency.unwrap(currency1)).transfer(address(modifyLiquidityRouter), fundAmount), "t1");

        // Current tick 120; range [-120, 0] is entirely below current tick -> only token1
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 0, liquidityDelta: 1000, salt: bytes32(0)});
        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(poolKey, params, ZERO_BYTES);

        assertEq(delta.amount0(), 0, "should not pay token0");
        assertLt(int256(delta.amount1()), 0, "should pay token1");
    }

    /// @notice Multiple positions same owner different salts: both succeed independently
    function test_modifyLiquidity_multiplePositions_differentSalts() public {
        uint256 fundAmount = 5e9;
        require(IERC20(Currency.unwrap(currency0)).transfer(address(modifyLiquidityRouter), fundAmount), "t0");
        require(IERC20(Currency.unwrap(currency1)).transfer(address(modifyLiquidityRouter), fundAmount), "t1");

        ModifyLiquidityParams memory params0 =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 500, salt: bytes32(0)});
        (BalanceDelta d0,) = modifyLiquidityRouter.modifyLiquidity(key, params0, ZERO_BYTES);
        assertLt(int256(d0.amount0()), 0);
        assertLt(int256(d0.amount1()), 0);

        ModifyLiquidityParams memory params1 =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 300, salt: bytes32(uint256(1))});
        (BalanceDelta d1,) = modifyLiquidityRouter.modifyLiquidity(key, params1, ZERO_BYTES);
        assertLt(int256(d1.amount0()), 0);
        assertLt(int256(d1.amount1()), 0);

        // Remove first position only
        ModifyLiquidityParams memory remove0 =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: -500, salt: bytes32(0)});
        (BalanceDelta r0,) = modifyLiquidityRouter.modifyLiquidity(key, remove0, ZERO_BYTES);
        assertGt(int256(r0.amount0()), 0);
        assertGt(int256(r0.amount1()), 0);
    }

    /// @notice Remove more liquidity than position has: reverts (liquidity underflow)
    function test_modifyLiquidity_removeMoreThanAdded_reverts() public {
        uint256 fundAmount = 5e9;
        require(IERC20(Currency.unwrap(currency0)).transfer(address(modifyLiquidityRouter), fundAmount), "t0");
        require(IERC20(Currency.unwrap(currency1)).transfer(address(modifyLiquidityRouter), fundAmount), "t1");

        ModifyLiquidityParams memory addParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000, salt: bytes32(0)});
        modifyLiquidityRouter.modifyLiquidity(key, addParams, ZERO_BYTES);

        ModifyLiquidityParams memory removeTooMuch = ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: -2000, // more than added
            salt: bytes32(0)
        });
        vm.expectRevert(); // LiquidityMath underflow or SafeCast
        modifyLiquidityRouter.modifyLiquidity(key, removeTooMuch, ZERO_BYTES);
    }

    /// @notice Adding liquidity that would exceed max per tick reverts with TickLiquidityOverflow
    function test_modifyLiquidity_tickLiquidityOverflow_reverts() public {
        // maxLiquidityPerTick for tickSpacing 60 is ~type(uint128).max/29576; use L that fits int128 but exceeds that
        uint128 overflowL = type(uint128).max / 29576 + 1;
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -120, tickUpper: 120, liquidityDelta: int256(uint256(overflowL)), salt: bytes32(0)
        });
        vm.expectRevert(abi.encodeWithSelector(TickLiquidityOverflow.selector, int24(-120)));
        modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);
    }

    /// @notice Fee delta is zero when no swaps have occurred (no fee growth)
    function test_modifyLiquidity_feeDelta_zeroWhenNoSwaps() public {
        uint256 fundAmount = 5e9;
        require(IERC20(Currency.unwrap(currency0)).transfer(address(modifyLiquidityRouter), fundAmount), "t0");
        require(IERC20(Currency.unwrap(currency1)).transfer(address(modifyLiquidityRouter), fundAmount), "t1");

        ModifyLiquidityParams memory addParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000, salt: bytes32(0)});
        modifyLiquidityRouter.modifyLiquidity(key, addParams, ZERO_BYTES);

        // Modify with zero delta (e.g. "claim"): no swaps so fee growth unchanged, feeDelta should be 0
        ModifyLiquidityParams memory claimParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 0, salt: bytes32(0)});
        (, BalanceDelta feeDelta) = modifyLiquidityRouter.modifyLiquidity(key, claimParams, ZERO_BYTES);
        assertEq(feeDelta.amount0(), 0, "fee0 zero when no swaps");
        assertEq(feeDelta.amount1(), 0, "fee1 zero when no swaps");
    }

    /// @notice Different tick ranges: narrow [-60,60] and wide [-120,120] both succeed
    function test_modifyLiquidity_differentTickRanges_bothSucceed() public {
        uint256 fundAmount = 5e9;
        require(IERC20(Currency.unwrap(currency0)).transfer(address(modifyLiquidityRouter), fundAmount), "t0");
        require(IERC20(Currency.unwrap(currency1)).transfer(address(modifyLiquidityRouter), fundAmount), "t1");

        ModifyLiquidityParams memory narrow =
            ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 800, salt: bytes32(0)});
        (BalanceDelta dNarrow,) = modifyLiquidityRouter.modifyLiquidity(key, narrow, ZERO_BYTES);
        assertLt(int256(dNarrow.amount0()), 0);
        assertLt(int256(dNarrow.amount1()), 0);

        ModifyLiquidityParams memory wide =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 500, salt: bytes32(uint256(1))});
        (BalanceDelta dWide,) = modifyLiquidityRouter.modifyLiquidity(key, wide, ZERO_BYTES);
        assertLt(int256(dWide.amount0()), 0);
        assertLt(int256(dWide.amount1()), 0);
    }

    /// @notice Boundary ticks (aligned): add at min/max aligned ticks for tickSpacing 60
    function test_modifyLiquidity_boundaryTicks_alignedSucceeds() public {
        int24 tickSpacing = 60;
        int24 tickLower = -887220; // -14787 * 60, aligned
        int24 tickUpper = 887220; // 14787 * 60, aligned
        uint160 sqrtPrice = SQRT_PRICE_1_1;
        (PoolKey memory poolKey,) = initPool(currency0, currency1, 2500, tickSpacing, sqrtPrice);

        uint256 fundAmount = 5e9;
        require(IERC20(Currency.unwrap(currency0)).transfer(address(modifyLiquidityRouter), fundAmount), "t0");
        require(IERC20(Currency.unwrap(currency1)).transfer(address(modifyLiquidityRouter), fundAmount), "t1");

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: 100, salt: bytes32(0)});
        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(poolKey, params, ZERO_BYTES);
        assertLt(int256(delta.amount0()), 0);
        assertLt(int256(delta.amount1()), 0);
    }

    /// @notice Position containing current tick: both token0 and token1 required
    function test_modifyLiquidity_positionContainsCurrentTick_bothTokensRequired() public {
        uint256 fundAmount = 5e9;
        require(IERC20(Currency.unwrap(currency0)).transfer(address(modifyLiquidityRouter), fundAmount), "t0");
        require(IERC20(Currency.unwrap(currency1)).transfer(address(modifyLiquidityRouter), fundAmount), "t1");

        // Pool at tick 0 (price 1:1); range [-120, 120] contains current tick; use small L so router has enough
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -120, tickUpper: 120, liquidityDelta: int256(uint256(1000)), salt: bytes32(0)
        });
        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);

        assertLt(int256(delta.amount0()), 0, "pay token0 when range contains tick");
        assertLt(int256(delta.amount1()), 0, "pay token1 when range contains tick");
    }

    /// @notice Same range, same salt, add twice: liquidity is cumulative; remove once with 2*L removes all
    function test_modifyLiquidity_addTwiceSamePosition_thenRemoveAll() public {
        uint256 fundAmount = 5e9;
        require(IERC20(Currency.unwrap(currency0)).transfer(address(modifyLiquidityRouter), fundAmount), "t0");
        require(IERC20(Currency.unwrap(currency1)).transfer(address(modifyLiquidityRouter), fundAmount), "t1");

        int256 L = 1000;
        ModifyLiquidityParams memory add =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: L, salt: bytes32(0)});
        modifyLiquidityRouter.modifyLiquidity(key, add, ZERO_BYTES);
        modifyLiquidityRouter.modifyLiquidity(key, add, ZERO_BYTES);

        ModifyLiquidityParams memory removeAll =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: -2 * L, salt: bytes32(0)});
        (BalanceDelta removeDelta,) = modifyLiquidityRouter.modifyLiquidity(key, removeAll, ZERO_BYTES);
        assertGt(int256(removeDelta.amount0()), 0);
        assertGt(int256(removeDelta.amount1()), 0);
    }

    /// @notice Add liquidity with 1:3 price (range [0.3, 0.4]); L chosen so required amounts fit HTS supply (5e9)
    function test_modifyLiquidity_addLiqudityWith1_3Price_succeeds() public {
        uint160 SQRT_PRICE_1_3 = 45746622930794429382959749662549926200;
        reinitPoolWithSqrtPrice(SQRT_PRICE_1_3);

        int24 tickLower = -12060;
        int24 tickUpper = -9120;

        // L large enough that amount0/amount1 are non-zero, but required amounts fit HTS supply (5e9)
        int256 L = 1000;
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: L, salt: bytes32(0)});

        uint256 fundAmount = 5e9;
        require(IERC20(Currency.unwrap(currency0)).transfer(address(modifyLiquidityRouter), fundAmount), "transfer0");
        require(IERC20(Currency.unwrap(currency1)).transfer(address(modifyLiquidityRouter), fundAmount), "transfer1");

        uint256 managerBal0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(manager));
        uint256 managerBal1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(manager));

        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);

        // Adding liquidity: we pay at least one token (current tick can be below, inside, or above range)
        assertTrue(delta.amount0() < 0 || delta.amount1() < 0, "should pay at least token0 or token1");

        uint256 paid0 = delta.amount0() < 0 ? uint256(uint128(-delta.amount0())) : 0;
        uint256 paid1 = delta.amount1() < 0 ? uint256(uint128(-delta.amount1())) : 0;

        assertEq(
            IERC20(Currency.unwrap(currency0)).balanceOf(address(manager)),
            managerBal0Before + paid0,
            "manager should have received token0"
        );
        assertEq(
            IERC20(Currency.unwrap(currency1)).balanceOf(address(manager)),
            managerBal1Before + paid1,
            "manager should have received token1"
        );

        // When both tokens are required (tick inside range), ratio paid0:paid1 ~ 1000:196
        if (paid0 > 0 && paid1 > 0) {
            assertApproxEqRel(paid0 * 196, paid1 * 1000, 0.05e18, "paid0:paid1 ~ 1000:196");
        }
    }
}
