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
import {SwapParams} from "../../src/types/SwapParams.sol";
import {IUnlockCallback} from "../../src/callback/IUnlockCallback.sol";
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

    // ========================================================================
    // FEE ACCRUAL TESTS — Swap then collect fees via modifyLiquidity
    // ========================================================================

    /// @notice After a swap, LP position accrues fees; claiming with zero-delta returns nonzero feeDelta (HTS-HTS)
    function test_feeAccrual_htsHts_afterSwap_feeDeltaNonZero() public {
        _fundRouter(5e9);

        // Add large liquidity so swap has room
        ModifyLiquidityParams memory addParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e9, salt: bytes32(0)});
        modifyLiquidityRouter.modifyLiquidity(key, addParams, ZERO_BYTES);

        // Fund router for swap
        _fundRouter(5e8);

        // Swap: exact input 10000 token0 -> token1
        SwapParams memory swapParams = SwapParams({
            amountSpecified: -10000,
            tickSpacing: 60,
            zeroForOne: true,
            sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
            lpFeeOverride: 0
        });
        modifyLiquidityRouter.swap(key, swapParams, ZERO_BYTES);

        // Claim fees: zero liquidityDelta
        ModifyLiquidityParams memory claimParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 0, salt: bytes32(0)});
        (, BalanceDelta feeDelta) = modifyLiquidityRouter.modifyLiquidity(key, claimParams, ZERO_BYTES);

        // Fee accrued on token0 (input side of zeroForOne swap); fee0 > 0, fee1 == 0
        assertGt(feeDelta.amount0(), 0, "fee0 should be positive after zeroForOne swap");
        assertEq(feeDelta.amount1(), 0, "fee1 should be 0 after zeroForOne swap");
    }

    /// @notice After a oneForZero swap, fee accrues on token1 side (HTS-HTS)
    function test_feeAccrual_htsHts_afterOneForZeroSwap() public {
        _fundRouter(5e9);

        ModifyLiquidityParams memory addParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e9, salt: bytes32(0)});
        modifyLiquidityRouter.modifyLiquidity(key, addParams, ZERO_BYTES);

        _fundRouter(5e8);

        // Swap: exact input token1 -> token0
        SwapParams memory swapParams = SwapParams({
            amountSpecified: -10000,
            tickSpacing: 60,
            zeroForOne: false,
            sqrtPriceLimitX96: TickMath.maxSqrtPrice() - 1,
            lpFeeOverride: 0
        });
        modifyLiquidityRouter.swap(key, swapParams, ZERO_BYTES);

        // Claim fees
        ModifyLiquidityParams memory claimParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 0, salt: bytes32(0)});
        (, BalanceDelta feeDelta) = modifyLiquidityRouter.modifyLiquidity(key, claimParams, ZERO_BYTES);

        assertEq(feeDelta.amount0(), 0, "fee0 should be 0 after oneForZero swap");
        assertGt(feeDelta.amount1(), 0, "fee1 should be positive after oneForZero swap");
    }

    /// @notice Fee accrual with ERC20-ERC20 pool: same behavior as HTS-HTS
    function test_feeAccrual_erc20Erc20_afterSwap() public {
        (PoolKey memory erc20Key,, Currency c0, Currency c1) = _setupERC20Pool(SQRT_PRICE_1_1, 3000, 60);

        // Fund for liquidity
        _fundRouterWithCurrencies(c0, c1, 1e17);

        ModifyLiquidityParams memory addParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e15, salt: bytes32(0)});
        modifyLiquidityRouter.modifyLiquidity(erc20Key, addParams, ZERO_BYTES);

        // Fund for swap
        _fundRouterWithCurrencies(c0, c1, 1e15);

        SwapParams memory swapParams = SwapParams({
            amountSpecified: -1e12,
            tickSpacing: 60,
            zeroForOne: true,
            sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
            lpFeeOverride: 0
        });
        modifyLiquidityRouter.swap(erc20Key, swapParams, ZERO_BYTES);

        ModifyLiquidityParams memory claimParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 0, salt: bytes32(0)});
        (, BalanceDelta feeDelta) = modifyLiquidityRouter.modifyLiquidity(erc20Key, claimParams, ZERO_BYTES);

        assertGt(feeDelta.amount0(), 0, "ERC20: fee0 positive after swap");
        assertEq(feeDelta.amount1(), 0, "ERC20: fee1 zero after zeroForOne");
    }

    /// @notice Fee accrual with mixed ERC20-HTS pool
    function test_feeAccrual_erc20Hts_afterSwap() public {
        (PoolKey memory mixedKey, Currency c0, Currency c1) = _setupMixedPool();

        _fundRouterWithCurrencies(c0, c1, 5e9);

        ModifyLiquidityParams memory addParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e9, salt: bytes32(0)});
        modifyLiquidityRouter.modifyLiquidity(mixedKey, addParams, ZERO_BYTES);

        _fundRouterWithCurrencies(c0, c1, 5e8);

        SwapParams memory swapParams = SwapParams({
            amountSpecified: -10000,
            tickSpacing: 60,
            zeroForOne: true,
            sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
            lpFeeOverride: 0
        });
        modifyLiquidityRouter.swap(mixedKey, swapParams, ZERO_BYTES);

        ModifyLiquidityParams memory claimParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 0, salt: bytes32(0)});
        (, BalanceDelta feeDelta) = modifyLiquidityRouter.modifyLiquidity(mixedKey, claimParams, ZERO_BYTES);

        assertGt(feeDelta.amount0(), 0, "mixed: fee0 positive after zeroForOne swap");
    }

    /// @notice Fees collected on remove: when removing after swap, callerDelta includes principal + fees
    function test_feeAccrual_htsHts_feesCollectedOnRemove() public {
        _fundRouter(5e9);

        int256 L = 1e9;
        ModifyLiquidityParams memory addParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: L, salt: bytes32(0)});
        (BalanceDelta addDelta,) = modifyLiquidityRouter.modifyLiquidity(key, addParams, ZERO_BYTES);
        uint256 paid0 = uint256(uint128(-addDelta.amount0()));

        // Swap to generate fees
        _fundRouter(5e8);
        SwapParams memory swapParams = SwapParams({
            amountSpecified: -100000,
            tickSpacing: 60,
            zeroForOne: true,
            sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
            lpFeeOverride: 0
        });
        modifyLiquidityRouter.swap(key, swapParams, ZERO_BYTES);

        // Remove all liquidity — should get principal + fees
        ModifyLiquidityParams memory removeParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: -L, salt: bytes32(0)});
        (BalanceDelta removeDelta, BalanceDelta feeDelta) =
            modifyLiquidityRouter.modifyLiquidity(key, removeParams, ZERO_BYTES);

        // Principal: get back approximately what we paid
        assertGt(removeDelta.amount0(), 0, "receive token0 on remove");
        assertGt(removeDelta.amount1(), 0, "receive token1 on remove");

        // Fee included in callerDelta: removeDelta.amount0 > paid0 because fees added
        uint256 received0 = uint256(uint128(removeDelta.amount0()));
        assertGt(received0, paid0, "received0 > paid0 due to fees");

        // feeDelta should also report fee amounts
        assertGt(feeDelta.amount0(), 0, "feeDelta0 positive");
    }

    /// @notice Multiple swaps in both directions: fees accrue on both token0 and token1
    function test_feeAccrual_htsHts_bidirectionalSwaps() public {
        _fundRouter(5e9);

        ModifyLiquidityParams memory addParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e9, salt: bytes32(0)});
        modifyLiquidityRouter.modifyLiquidity(key, addParams, ZERO_BYTES);

        // Swap zeroForOne
        _fundRouter(5e8);
        modifyLiquidityRouter.swap(
            key,
            SwapParams({
                amountSpecified: -50000,
                tickSpacing: 60,
                zeroForOne: true,
                sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
                lpFeeOverride: 0
            }),
            ZERO_BYTES
        );

        // Swap oneForZero
        _fundRouter(5e8);
        modifyLiquidityRouter.swap(
            key,
            SwapParams({
                amountSpecified: -50000,
                tickSpacing: 60,
                zeroForOne: false,
                sqrtPriceLimitX96: TickMath.maxSqrtPrice() - 1,
                lpFeeOverride: 0
            }),
            ZERO_BYTES
        );

        // Claim fees
        ModifyLiquidityParams memory claimParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 0, salt: bytes32(0)});
        (, BalanceDelta feeDelta) = modifyLiquidityRouter.modifyLiquidity(key, claimParams, ZERO_BYTES);

        assertGt(feeDelta.amount0(), 0, "fee0 positive after bidirectional swaps");
        assertGt(feeDelta.amount1(), 0, "fee1 positive after bidirectional swaps");
    }

    // ========================================================================
    // DIFFERENT FEE TIERS — 500 (0.05%), 3000 (0.3%), 10000 (1%)
    // ========================================================================

    /// @notice Low fee tier (500 = 0.05%): verify add liquidity works with HTS-HTS
    function test_addLiquidity_htsHts_lowFeeTier() public {
        (PoolKey memory lowFeeKey,) = initPool(currency0, currency1, 500, 10, SQRT_PRICE_1_1);
        _fundRouter(5e9);

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 1e9, salt: bytes32(0)});
        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(lowFeeKey, params, ZERO_BYTES);

        assertLt(delta.amount0(), 0, "pay token0");
        assertLt(delta.amount1(), 0, "pay token1");
    }

    /// @notice High fee tier (10000 = 1%): verify add liquidity works with ERC20-ERC20
    function test_addLiquidity_erc20Erc20_highFeeTier() public {
        (PoolKey memory erc20Key,, Currency c0, Currency c1) = _setupERC20Pool(SQRT_PRICE_1_1, 10000, 200);

        _fundRouterWithCurrencies(c0, c1, 1e17);

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -200, tickUpper: 200, liquidityDelta: 1e15, salt: bytes32(0)});
        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(erc20Key, params, ZERO_BYTES);

        assertLt(delta.amount0(), 0, "ERC20 high fee: pay token0");
        assertLt(delta.amount1(), 0, "ERC20 high fee: pay token1");
    }

    /// @notice Low fee tier collects less fees than high fee tier for same swap amount
    function test_feeAccrual_lowVsHighFeeTier_comparison() public {
        // Low fee pool (500 = 0.05%, tickSpacing 10)
        (PoolKey memory lowKey,) = initPool(currency0, currency1, 500, 10, SQRT_PRICE_1_1);
        _fundRouter(5e9);
        modifyLiquidityRouter.modifyLiquidity(
            lowKey,
            ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 1e9, salt: bytes32(0)}),
            ZERO_BYTES
        );

        // High fee pool (10000 = 1%, tickSpacing 200) — use new ERC20 pair to avoid collision
        (PoolKey memory highKey,, Currency c0h, Currency c1h) = _setupERC20Pool(SQRT_PRICE_1_1, 10000, 200);
        _fundRouterWithCurrencies(c0h, c1h, 1e17);
        modifyLiquidityRouter.modifyLiquidity(
            highKey,
            ModifyLiquidityParams({tickLower: -200, tickUpper: 200, liquidityDelta: 1e15, salt: bytes32(0)}),
            ZERO_BYTES
        );

        // Swap same amount on low-fee HTS pool
        _fundRouter(5e8);
        modifyLiquidityRouter.swap(
            lowKey,
            SwapParams({
                amountSpecified: -10000,
                tickSpacing: 10,
                zeroForOne: true,
                sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
                lpFeeOverride: 0
            }),
            ZERO_BYTES
        );
        (, BalanceDelta feeLow) = modifyLiquidityRouter.modifyLiquidity(
            lowKey,
            ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 0, salt: bytes32(0)}),
            ZERO_BYTES
        );

        // Swap same amount on high-fee ERC20 pool
        _fundRouterWithCurrencies(c0h, c1h, 1e15);
        modifyLiquidityRouter.swap(
            highKey,
            SwapParams({
                amountSpecified: -10000,
                tickSpacing: 200,
                zeroForOne: true,
                sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
                lpFeeOverride: 0
            }),
            ZERO_BYTES
        );
        (, BalanceDelta feeHigh) = modifyLiquidityRouter.modifyLiquidity(
            highKey,
            ModifyLiquidityParams({tickLower: -200, tickUpper: 200, liquidityDelta: 0, salt: bytes32(0)}),
            ZERO_BYTES
        );

        // High fee tier should collect more fees
        assertGt(feeHigh.amount0(), feeLow.amount0(), "high fee tier collects more fees than low");
    }

    // ========================================================================
    // TICK SPACING VARIATIONS
    // ========================================================================

    /// @notice tickSpacing = 1: finest granularity, add liquidity at [-1, 1]
    function test_addLiquidity_htsHts_tickSpacing1() public {
        (PoolKey memory key1,) = initPool(currency0, currency1, 100, 1, SQRT_PRICE_1_1);
        _fundRouter(5e9);

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -1, tickUpper: 1, liquidityDelta: 1e9, salt: bytes32(0)});
        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(key1, params, ZERO_BYTES);

        assertLt(delta.amount0(), 0, "tickSpacing=1: pay token0");
        assertLt(delta.amount1(), 0, "tickSpacing=1: pay token1");
    }

    /// @notice tickSpacing = 200: coarse granularity with ERC20
    function test_addLiquidity_erc20Erc20_tickSpacing200() public {
        (PoolKey memory erc20Key,, Currency c0, Currency c1) = _setupERC20Pool(SQRT_PRICE_1_1, 3000, 200);
        _fundRouterWithCurrencies(c0, c1, 1e17);

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -200, tickUpper: 200, liquidityDelta: 1e15, salt: bytes32(0)});
        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(erc20Key, params, ZERO_BYTES);

        assertLt(delta.amount0(), 0);
        assertLt(delta.amount1(), 0);
    }

    // ========================================================================
    // DIFFERENT INITIAL PRICES — Test asymmetric token amounts
    // ========================================================================

    /// @notice Price 2:1 (SQRT_PRICE_2_1): more token1 required, less token0 (HTS-HTS)
    function test_addLiquidity_htsHts_price2to1() public {
        reinitPoolWithSqrtPrice(SQRT_PRICE_2_1);
        _fundRouter(5e9);

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000, salt: bytes32(0)});
        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);

        // At price 2:1, pool tick is positive; range [-120, 120] contains tick 0..6931
        // Both tokens required but ratio shifts
        assertTrue(delta.amount0() < 0 || delta.amount1() < 0, "pay at least one token");
    }

    /// @notice Price 1:4 (SQRT_PRICE_1_4): HTS-HTS at very skewed ratio
    function test_addLiquidity_htsHts_price1to4() public {
        reinitPoolWithSqrtPrice(SQRT_PRICE_1_4);
        _fundRouter(5e9);

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000, salt: bytes32(0)});
        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);

        assertTrue(delta.amount0() < 0 || delta.amount1() < 0, "pay at least one token at 1:4");
    }

    /// @notice Price 4:1 (SQRT_PRICE_4_1): ERC20-ERC20 at high skew
    function test_addLiquidity_erc20Erc20_price4to1() public {
        (PoolKey memory erc20Key,, Currency c0, Currency c1) = _setupERC20Pool(SQRT_PRICE_4_1, 3000, 60);
        _fundRouterWithCurrencies(c0, c1, 1e17);

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e15, salt: bytes32(0)});
        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(erc20Key, params, ZERO_BYTES);

        assertTrue(delta.amount0() < 0 || delta.amount1() < 0, "ERC20 4:1: pay at least one token");
    }

    /// @notice Price 1:2 (SQRT_PRICE_1_2): mixed ERC20-HTS
    function test_addLiquidity_erc20Hts_price1to2() public {
        MockERC20 mockErc20 = new MockERC20();
        mockErc20.mint(address(this), 1e18);
        address erc20Addr = address(mockErc20);
        address htsAddr = Currency.unwrap(currency0);
        (Currency c0, Currency c1) =
            erc20Addr < htsAddr ? (Currency.wrap(erc20Addr), currency0) : (currency0, Currency.wrap(erc20Addr));
        mockErc20.approve(address(modifyLiquidityRouter), type(uint256).max);

        (PoolKey memory poolKey,) = initPool(c0, c1, 3000, 60, SQRT_PRICE_1_2);

        _fundRouterWithCurrencies(c0, c1, 5e9);

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000, salt: bytes32(0)});
        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(poolKey, params, ZERO_BYTES);

        assertTrue(delta.amount0() < 0 || delta.amount1() < 0, "mixed 1:2: pay at least one token");
    }

    // ========================================================================
    // LARGE LIQUIDITY VALUES — Stress test with HTS and ERC20
    // ========================================================================

    /// @notice Large liquidity add with ERC20 (1e18): verify no overflow
    function test_addLiquidity_erc20Erc20_largeLiquidity() public {
        (PoolKey memory erc20Key,, Currency c0, Currency c1) = _setupERC20Pool(SQRT_PRICE_1_1, 3000, 60);
        _fundRouterWithCurrencies(c0, c1, 5e17);

        int256 largeLiquidity = 1e16;
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: largeLiquidity, salt: bytes32(0)});
        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(erc20Key, params, ZERO_BYTES);

        assertLt(delta.amount0(), 0, "large L: pay token0");
        assertLt(delta.amount1(), 0, "large L: pay token1");
    }

    /// @notice Small liquidity (1 wei): can add and remove
    function test_addLiquidity_htsHts_minimalLiquidity() public {
        _fundRouter(5e9);

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1, salt: bytes32(0)});
        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);

        // Delta may be zero for very small L due to rounding
        assertTrue(delta.amount0() <= 0 && delta.amount1() <= 0, "minimal L: non-positive deltas");

        // Remove
        ModifyLiquidityParams memory removeParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: -1, salt: bytes32(0)});
        (BalanceDelta removeDelta,) = modifyLiquidityRouter.modifyLiquidity(key, removeParams, ZERO_BYTES);
        assertTrue(removeDelta.amount0() >= 0 && removeDelta.amount1() >= 0, "minimal L: non-negative remove deltas");
    }

    // ========================================================================
    // CONCURRENT POSITIONS — Multiple LPs, multiple token types, overlapping ranges
    // ========================================================================

    /// @notice Two LP positions at overlapping ranges in same HTS-HTS pool, then swap: both collect fees
    function test_feeAccrual_htsHts_twoPositionsOverlapping_bothCollectFees() public {
        _fundRouter(5e9);

        // Position A: [-120, 120]
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e9, salt: bytes32(0)}),
            ZERO_BYTES
        );

        // Position B: [-60, 60] (narrower, overlapping)
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 1e9, salt: bytes32(uint256(1))}),
            ZERO_BYTES
        );

        // Swap to generate fees
        _fundRouter(5e8);
        modifyLiquidityRouter.swap(
            key,
            SwapParams({
                amountSpecified: -50000,
                tickSpacing: 60,
                zeroForOne: true,
                sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
                lpFeeOverride: 0
            }),
            ZERO_BYTES
        );

        // Claim fees for position A
        (, BalanceDelta feeA) = modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 0, salt: bytes32(0)}),
            ZERO_BYTES
        );

        // Claim fees for position B
        (, BalanceDelta feeB) = modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 0, salt: bytes32(uint256(1))}),
            ZERO_BYTES
        );

        assertGt(feeA.amount0(), 0, "position A: fee0 positive");
        assertGt(feeB.amount0(), 0, "position B: fee0 positive");

        // Narrower position B should get more fee per liquidity (higher concentration)
        // But since same L and B is narrower, it gets proportionally more when tick is in range
        // Both should have positive fees; exact ratio depends on swap path
    }

    /// @notice Two positions: one HTS-HTS, one ERC20-ERC20, same price — independent pools
    function test_addLiquidity_htsAndErc20_independentPools() public {
        // HTS-HTS pool already set up
        _fundRouter(5e9);
        (BalanceDelta htsDelta,) = modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000, salt: bytes32(0)}),
            ZERO_BYTES
        );

        // ERC20-ERC20 pool
        (PoolKey memory erc20Key,, Currency c0, Currency c1) = _setupERC20Pool(SQRT_PRICE_1_1, 3000, 60);
        _fundRouterWithCurrencies(c0, c1, 1e17);
        (BalanceDelta erc20Delta,) = modifyLiquidityRouter.modifyLiquidity(
            erc20Key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000, salt: bytes32(0)}),
            ZERO_BYTES
        );

        // Both should succeed independently with same L and range
        assertLt(htsDelta.amount0(), 0, "HTS pool: pay token0");
        assertLt(erc20Delta.amount0(), 0, "ERC20 pool: pay token0");
        // Same L at same price and range → same amounts (modulo token decimals)
        assertEq(htsDelta.amount0(), erc20Delta.amount0(), "same L produces same amount0");
        assertEq(htsDelta.amount1(), erc20Delta.amount1(), "same L produces same amount1");
    }

    // ========================================================================
    // WIDE RANGE / FULL RANGE POSITIONS
    // ========================================================================

    /// @notice Full-range position: tickLower = MIN_TICK_ALIGNED, tickUpper = MAX_TICK_ALIGNED
    function test_addLiquidity_htsHts_fullRange() public {
        _fundRouter(5e9);

        int24 tickSpacing = 60;
        int24 tickLower = -887220; // -14787 * 60
        int24 tickUpper = 887220; // 14787 * 60

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: 100, salt: bytes32(0)});
        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);

        assertLt(delta.amount0(), 0, "full range: pay token0");
        assertLt(delta.amount1(), 0, "full range: pay token1");
    }

    /// @notice Full-range with ERC20 then swap and collect fees
    function test_feeAccrual_erc20Erc20_fullRange_afterSwap() public {
        (PoolKey memory erc20Key,, Currency c0, Currency c1) = _setupERC20Pool(SQRT_PRICE_1_1, 3000, 60);
        _fundRouterWithCurrencies(c0, c1, 1e17);

        int24 tickLower = -887220;
        int24 tickUpper = 887220;

        modifyLiquidityRouter.modifyLiquidity(
            erc20Key,
            ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: 1e15, salt: bytes32(0)}),
            ZERO_BYTES
        );

        _fundRouterWithCurrencies(c0, c1, 1e15);
        modifyLiquidityRouter.swap(
            erc20Key,
            SwapParams({
                amountSpecified: -1e12,
                tickSpacing: 60,
                zeroForOne: true,
                sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
                lpFeeOverride: 0
            }),
            ZERO_BYTES
        );

        (, BalanceDelta feeDelta) = modifyLiquidityRouter.modifyLiquidity(
            erc20Key,
            ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: 0, salt: bytes32(0)}),
            ZERO_BYTES
        );

        assertGt(feeDelta.amount0(), 0, "full range ERC20: fee0 after swap");
    }

    // ========================================================================
    // POOL STATE VERIFICATION — Check on-chain state after operations
    // ========================================================================

    /// @notice After adding liquidity, getPoolState returns same price and tick (no price change)
    function test_addLiquidity_htsHts_poolStateUnchanged() public {
        _fundRouter(5e9);

        (bool initBefore, uint160 priceBefore, int24 tickBefore) =
            PoolManager(address(manager)).getPoolState(key.toId());
        assertTrue(initBefore, "pool initialized before");

        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e9, salt: bytes32(0)}),
            ZERO_BYTES
        );

        (bool initAfter, uint160 priceAfter, int24 tickAfter) = PoolManager(address(manager)).getPoolState(key.toId());
        assertTrue(initAfter, "pool still initialized");
        assertEq(priceAfter, priceBefore, "price unchanged after add liquidity");
        assertEq(tickAfter, tickBefore, "tick unchanged after add liquidity");
    }

    /// @notice After swap + remove all liquidity, pool is still initialized but empty
    function test_removeLiquidity_htsHts_poolStillInitializedWhenEmpty() public {
        _fundRouter(5e9);

        int256 L = 1e9;
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: L, salt: bytes32(0)}),
            ZERO_BYTES
        );

        // Remove all
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: -L, salt: bytes32(0)}),
            ZERO_BYTES
        );

        (bool init, uint160 price,) = PoolManager(address(manager)).getPoolState(key.toId());
        assertTrue(init, "pool still initialized after removing all liquidity");
        assertGt(price, 0, "price still set");
    }

    // ========================================================================
    // SETTLEMENT EDGE CASES
    // ========================================================================

    /// @notice Unlock without settling reverts with CurrencyNotSettled
    function test_modifyLiquidity_revertWhen_currencyNotSettled() public {
        NoSettleRouter noSettle = new NoSettleRouter(manager);
        _fundRouter(5e9);

        vm.expectRevert(IPoolManager.CurrencyNotSettled.selector);
        noSettle.modifyLiquidityNoSettle(
            key, ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000, salt: bytes32(0)})
        );
    }

    /// @notice Double unlock reverts with AlreadyUnlocked
    function test_unlock_revertWhen_alreadyUnlocked() public {
        DoubleUnlockRouter doubleRouter = new DoubleUnlockRouter(manager);
        vm.expectRevert(IPoolManager.AlreadyUnlocked.selector);
        doubleRouter.attemptDoubleUnlock();
    }

    // ========================================================================
    // HOOKDATA PASSTHROUGH
    // ========================================================================

    /// @notice hookData is accepted and doesn't affect behavior (no hooks set)
    function test_modifyLiquidity_hookDataPassthrough() public {
        _fundRouter(5e9);

        bytes memory customHookData = abi.encode("custom_hook_data", uint256(42));
        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000, salt: bytes32(0)});
        (BalanceDelta delta,) = modifyLiquidityRouter.modifyLiquidity(key, params, customHookData);

        assertLt(delta.amount0(), 0, "hookData: pay token0 normally");
        assertLt(delta.amount1(), 0, "hookData: pay token1 normally");
    }

    // ========================================================================
    // ADD → SWAP → ADD MORE → REMOVE ALL LIFECYCLE
    // ========================================================================

    /// @notice Full lifecycle: add → swap → add more → remove all; verify final balances (HTS-HTS)
    function test_lifecycle_htsHts_addSwapAddRemoveAll() public {
        _fundRouter(5e9);

        int256 L1 = 1e9;
        int256 L2 = 5e8;

        // Step 1: Add initial liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: L1, salt: bytes32(0)}),
            ZERO_BYTES
        );

        // Step 2: Swap
        _fundRouter(5e8);
        modifyLiquidityRouter.swap(
            key,
            SwapParams({
                amountSpecified: -50000,
                tickSpacing: 60,
                zeroForOne: true,
                sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
                lpFeeOverride: 0
            }),
            ZERO_BYTES
        );

        // Step 3: Add more liquidity (same range, same salt → cumulative)
        _fundRouter(5e8);
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: L2, salt: bytes32(0)}),
            ZERO_BYTES
        );

        // Step 4: Remove all (L1 + L2)
        (BalanceDelta removeDelta, BalanceDelta feeDelta) = modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: -(L1 + L2), salt: bytes32(0)}),
            ZERO_BYTES
        );

        assertGt(removeDelta.amount0(), 0, "lifecycle: receive token0");
        assertGt(removeDelta.amount1(), 0, "lifecycle: receive token1");
        // Fee from L2 deposit (L2 joined after swap, so it gets fee from add time, not prior swap)
        // But the position has accumulated fees from both L1 and L2 portions
    }

    /// @notice Full lifecycle with ERC20-ERC20
    function test_lifecycle_erc20Erc20_addSwapRemove() public {
        (PoolKey memory erc20Key,, Currency c0, Currency c1) = _setupERC20Pool(SQRT_PRICE_1_1, 3000, 60);
        _fundRouterWithCurrencies(c0, c1, 1e17);

        int256 L = 1e15;

        // Add
        modifyLiquidityRouter.modifyLiquidity(
            erc20Key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: L, salt: bytes32(0)}),
            ZERO_BYTES
        );

        // Swap
        _fundRouterWithCurrencies(c0, c1, 1e15);
        modifyLiquidityRouter.swap(
            erc20Key,
            SwapParams({
                amountSpecified: -1e12,
                tickSpacing: 60,
                zeroForOne: true,
                sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
                lpFeeOverride: 0
            }),
            ZERO_BYTES
        );

        // Remove + collect fees
        (BalanceDelta removeDelta, BalanceDelta feeDelta) = modifyLiquidityRouter.modifyLiquidity(
            erc20Key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: -L, salt: bytes32(0)}),
            ZERO_BYTES
        );

        assertGt(removeDelta.amount0(), 0, "ERC20 lifecycle: receive token0");
        assertGt(removeDelta.amount1(), 0, "ERC20 lifecycle: receive token1");
        assertGt(feeDelta.amount0(), 0, "ERC20 lifecycle: fee0 collected");
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    /// @notice Fund router with both HTS currencies
    function _fundRouter(uint256 amount) internal {
        IERC20(Currency.unwrap(currency0)).transfer(address(modifyLiquidityRouter), amount);
        IERC20(Currency.unwrap(currency1)).transfer(address(modifyLiquidityRouter), amount);
    }

    /// @notice Fund router with arbitrary currencies
    function _fundRouterWithCurrencies(Currency c0, Currency c1, uint256 amount) internal {
        IERC20(Currency.unwrap(c0)).transfer(address(modifyLiquidityRouter), amount);
        IERC20(Currency.unwrap(c1)).transfer(address(modifyLiquidityRouter), amount);
    }

    /// @notice Setup an ERC20-ERC20 pool and return key + currencies
    function _setupERC20Pool(uint160 sqrtPrice, uint24 fee, int24 tickSpacing)
        internal
        returns (PoolKey memory poolKey, PoolId id, Currency c0, Currency c1)
    {
        MockERC20 mock0 = new MockERC20();
        MockERC20 mock1 = new MockERC20();
        mock0.mint(address(this), 1e18);
        mock1.mint(address(this), 1e18);
        address a0 = address(mock0);
        address a1 = address(mock1);
        (c0, c1) = a0 < a1 ? (Currency.wrap(a0), Currency.wrap(a1)) : (Currency.wrap(a1), Currency.wrap(a0));
        mock0.approve(address(modifyLiquidityRouter), type(uint256).max);
        mock1.approve(address(modifyLiquidityRouter), type(uint256).max);
        (poolKey, id) = initPool(c0, c1, fee, tickSpacing, sqrtPrice);
    }

    /// @notice Setup a mixed ERC20-HTS pool; returns sorted key and currencies
    function _setupMixedPool() internal returns (PoolKey memory poolKey, Currency c0, Currency c1) {
        MockERC20 mockErc20 = new MockERC20();
        mockErc20.mint(address(this), 1e18);
        address erc20Addr = address(mockErc20);
        address htsAddr = Currency.unwrap(currency0);
        (c0, c1) = erc20Addr < htsAddr ? (Currency.wrap(erc20Addr), currency0) : (currency0, Currency.wrap(erc20Addr));
        mockErc20.approve(address(modifyLiquidityRouter), type(uint256).max);
        (poolKey,) = initPool(c0, c1, 3000, 60, SQRT_PRICE_1_1);
    }
}

// ========================================================================
// AUXILIARY TEST CONTRACTS
// ========================================================================

/// @notice Router that calls modifyLiquidity but doesn't settle (tests CurrencyNotSettled)
contract NoSettleRouter is IUnlockCallback {
    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function modifyLiquidityNoSettle(PoolKey memory key, ModifyLiquidityParams memory params) external {
        manager.unlock(abi.encode(key, params));
    }

    function unlockCallback(bytes calldata rawData) external override returns (bytes memory) {
        require(msg.sender == address(manager), "NoSettleRouter: only manager");
        (PoolKey memory key, ModifyLiquidityParams memory params) =
            abi.decode(rawData, (PoolKey, ModifyLiquidityParams));
        manager.modifyLiquidity(key, params, "");
        // Intentionally do not settle — NonzeroDeltaCount != 0 → revert
        return "";
    }
}

/// @notice Router that attempts to call unlock twice (tests AlreadyUnlocked)
contract DoubleUnlockRouter is IUnlockCallback {
    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function attemptDoubleUnlock() external {
        manager.unlock(abi.encode(uint8(1)));
    }

    function unlockCallback(bytes calldata) external override returns (bytes memory) {
        require(msg.sender == address(manager), "DoubleUnlockRouter: only manager");
        // Attempt second unlock while already unlocked
        manager.unlock("");
        return "";
    }
}
