// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {PoolKey, TokensMustBeSorted, InvalidTickSpacing} from "../src/types/PoolKey.sol";
import {PoolId} from "../src/types/PoolId.sol";
import {MIN_TICK_SPACING, MAX_TICK_SPACING} from "../src/constants.sol";
import {ModifyLiquidityParams} from "../src/types/ModifyLiquidityParams.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {Currency} from "../src/types/Currency.sol";
import {Deployers} from "./utils/Deployers.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {IERC20} from "hedera-forking/IERC20.sol";

/// @notice Tests for PoolManager.modifyLiquidity (Uniswap v4-style setup).
/// @dev On Hedera, the native token (HBAR) is HTS-native (tokenized at consensus), so we treat token types as HTS and ERC20.
///   Hedera combinations (2^2 - 1 invalid = 3 valid pairs): HTS-HTS, ERC20-ERC20, HTS-ERC20 (and ERC20-HTS by address order).
///   We also test EVM-native (address(0)) for cross-chain: Native-ERC20, Native-HTS, Native-Native (reverts).
///   Total: 1. HTS-HTS  2. ERC20-ERC20  3. ERC20-HTS  4. HTS-ERC20  5. Native-ERC20  6. Native-HTS  7. Native-Native (reverts)
contract PoolManagerModifyLiquidityTest is Test, Deployers {
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
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: int256(uint256(1e18)),
            salt: bytes32(0)
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

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 1000,
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

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 1000,
            salt: bytes32(0)
        });
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

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 1000,
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

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 1000,
            salt: bytes32(0)
        });
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

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 1000,
            salt: bytes32(0)
        });
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
}
