// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {htsSetup} from "hedera-forking/htsSetup.sol";
import {HTS_ADDRESS} from "hedera-forking/HtsSystemContract.sol";
import {IHederaTokenService} from "hedera-forking/IHederaTokenService.sol";
import {HederaResponseCodes} from "hedera-forking/HederaResponseCodes.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {Currency} from "../src/types/Currency.sol";
import {ModifyLiquidityParams, SwapParams} from "../src/types/PoolOperation.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {MIN_TICK_SPACING, MAX_TICK_SPACING} from "../src/math/constants.sol";
import {PoolState} from "../src/types/PoolState.sol";
import {PoolId} from "../src/types/PoolKey.sol";
import {TickMath} from "../src/libraries/TickMath.sol";

/// @notice Exposes pool tick state for tests (liquidityGross, liquidityNet at ticks).
contract PoolManagerTestHarness is PoolManager {
    function getTickInfo(PoolId id, int24 tick) external view returns (uint128 liquidityGross, int128 liquidityNet) {
        PoolState storage pool = _getPool(id);
        return (pool.ticks[tick].liquidityGross, pool.ticks[tick].liquidityNet);
    }

    /// @notice Returns the tickBitmap word at wordPos for a pool (for tests).
    function getTickBitmapWord(PoolId id, int16 wordPos) external view returns (uint256) {
        PoolState storage pool = _getPool(id);
        return pool.tickBitmap[wordPos];
    }

    /// @notice Exposes _pools.slot for storage layout tests (slot of _pools in PoolManager).
    function getPoolsSlot() external pure returns (uint256) {
        return 0; // _pools is first state var in PoolManager
    }
}

/**
 * Tests for PoolManager using HTS (Hedera Token Service) tokens only.
 * Requires --ffi; use --fork-url for mirror node if needed.
 */
contract PoolManagerTest is Test {
    PoolManagerTestHarness public poolManager;
    address internal signer;
    address internal tokenA;
    address internal tokenB;

    /// @notice Converts a uint256 to a base-2 string (0s and 1s), MSB first.
    function _toBinaryString(uint256 x) internal pure returns (string memory) {
        if (x == 0) return "0";
        string memory s;
        while (x > 0) {
            s = string.concat((x & 1 == 1 ? "1" : "0"), s);
            x >>= 1;
        }
        return s;
    }

    function setUp() external {
        htsSetup();
        poolManager = new PoolManagerTestHarness();
        signer = makeAddr("signer");
        vm.deal(signer, 100 ether);

        tokenA = _createHTSToken("Token A", "TKA");
        tokenB = _createHTSToken("Token B", "TKB");
    }

    function _createHTSToken(string memory name, string memory symbol) internal returns (address) {
        IHederaTokenService.KeyValue memory keyValue;
        keyValue.inheritAccountKey = true;

        IHederaTokenService.HederaToken memory token;
        token.name = name;
        token.symbol = symbol;
        token.treasury = signer;
        token.memo = "";
        token.tokenKeys = new IHederaTokenService.TokenKey[](2);
        token.tokenKeys[0] = IHederaTokenService.TokenKey(0x1, keyValue);
        token.tokenKeys[1] = IHederaTokenService.TokenKey(0x10, keyValue);
        token.expiry = IHederaTokenService.Expiry(0, signer, 8000000);

        vm.prank(signer);
        (int64 responseCode, address tokenAddress) =
            IHederaTokenService(HTS_ADDRESS).createFungibleToken{value: 10 ether}(token, 1e18, 18);

        require(responseCode == HederaResponseCodes.SUCCESS, "createFungibleToken failed");
        require(tokenAddress != address(0), "token address zero");
        return tokenAddress;
    }

    function _validPoolKey() internal view returns (PoolKey memory key) {
        (Currency t0, Currency t1) = tokenA < tokenB
            ? (Currency.wrap(tokenA), Currency.wrap(tokenB))
            : (Currency.wrap(tokenB), Currency.wrap(tokenA));
        key.token0 = t0;
        key.token1 = t1;
        key.fee = 3000;
        key.tickSpacing = 60;
        key.hooks = IHooks(address(0));
    }

    function test_initialize_revertWhenTickSpacingTooSmall() external {
        PoolKey memory key = _validPoolKey();
        key.tickSpacing = 0;

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooSmall.selector, int24(0)));
        poolManager.initialize(key, 1);
    }

    function test_initialize_revertWhenTickSpacingTooSmall_negative() external {
        PoolKey memory key = _validPoolKey();
        key.tickSpacing = -1;

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooSmall.selector, int24(-1)));
        poolManager.initialize(key, 1);
    }

    function test_initialize_revertWhenTickSpacingTooLarge() external {
        PoolKey memory key = _validPoolKey();
        key.tickSpacing = int24(int256(type(int16).max) + 1);

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.TickSpacingTooLarge.selector, key.tickSpacing));
        poolManager.initialize(key, 1);
    }

    function test_initialize_revertWhenCurrenciesOutOfOrder() external {
        PoolKey memory key = _validPoolKey();
        key.token0 = Currency.wrap(tokenB);
        key.token1 = Currency.wrap(tokenA);

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.CurrenciesOutOfOrderOrEqual.selector, tokenB, tokenA));
        poolManager.initialize(key, 1);
    }

    function test_initialize_revertWhenCurrenciesEqual() external {
        PoolKey memory key = _validPoolKey();
        key.token0 = Currency.wrap(tokenA);
        key.token1 = Currency.wrap(tokenA);

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.CurrenciesOutOfOrderOrEqual.selector, tokenA, tokenA));
        poolManager.initialize(key, 1);
    }

    function test_initialize_success() external {
        PoolKey memory key = _validPoolKey();
        uint160 sqrtPriceX96 = 79228162514264337593543950336;

        int24 tick = poolManager.initialize(key, sqrtPriceX96);

        assertEq(tick, 0);
    }

    function test_initialize_success_minTickSpacing() external {
        PoolKey memory key = _validPoolKey();
        key.tickSpacing = MIN_TICK_SPACING;

        uint160 sqrtPriceX96 = uint160(2 ** 96);
        int24 tick = poolManager.initialize(key, sqrtPriceX96);
        assertEq(tick, 0);
    }

    function test_initialize_success_maxTickSpacing() external {
        PoolKey memory key = _validPoolKey();
        key.tickSpacing = MAX_TICK_SPACING;

        uint160 sqrtPriceX96 = uint160(2 ** 96);
        int24 tick = poolManager.initialize(key, sqrtPriceX96);
        assertEq(tick, 0);
    }

    function test_swap_revertWhenAmountSpecifiedZero() external {
        PoolKey memory key = _validPoolKey();
        poolManager.initialize(key, uint160(2 ** 96));

        SwapParams memory params =
            SwapParams({amountSpecified: 0, tickSpacing: 60, zeroForOne: true, sqrtPriceLimitX96: 0, lpFeeOverride: 0});

        vm.expectRevert(IPoolManager.SwapAmountCannotBeZero.selector);
        poolManager.swap(key, params, "");
    }

    function test_swap_revertWhenPoolNotInitialized() external {
        PoolKey memory key = _validPoolKey();
        // Do not call initialize(key, ...) so the pool does not exist.

        SwapParams memory params = SwapParams({
            amountSpecified: -1000, // non-zero so we pass the first check and hit checkPoolInitialized
            tickSpacing: 60,
            zeroForOne: true,
            sqrtPriceLimitX96: 0,
            lpFeeOverride: 0
        });

        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        poolManager.swap(key, params, "");
    }

    function test_modifyLiquidity_revertWhenPoolNotInitialized() external {
        PoolKey memory key = _validPoolKey();
        // Do not call initialize(key, ...) so the pool does not exist.

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            owner: signer, tickLower: -60, tickUpper: 60, liquidityDelta: 1000, tickSpacing: 60, salt: bytes32(0)
        });

        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        poolManager.modifyLiquidity(key, params, "");
    }

    /// @notice Add liquidity to a 1:1 ETH/USDT pool and assert liquidityGross and liquidityNet at tick boundaries.
    function test_modifyLiquidity_addLiquidity_1to1_ETH_USDT_tickInfoGrossAndNet() external {
        address eth = _createHTSToken("Ethereum", "ETH");
        address usdt = _createHTSToken("Tether USD", "USDT");

        (Currency t0, Currency t1) =
            eth < usdt ? (Currency.wrap(eth), Currency.wrap(usdt)) : (Currency.wrap(usdt), Currency.wrap(eth));

        PoolKey memory key = PoolKey({token0: t0, token1: t1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))});

        // 1:1 price => sqrt(1) in Q64.96 = 2^96
        uint160 sqrtPriceX96 = uint160(2 ** 96);
        poolManager.initialize(key, sqrtPriceX96);

        int24 tickLower = -60;
        int24 tickUpper = 60;
        int128 liquidityDelta = 1000;

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            owner: signer,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: liquidityDelta,
            tickSpacing: 60,
            salt: bytes32(0)
        });

        poolManager.modifyLiquidity(key, params, "");

        PoolId id = key.toId();

        (uint128 grossLower, int128 netLower) = poolManager.getTickInfo(id, tickLower);
        assertEq(grossLower, uint128(int128(liquidityDelta)), "tickLower liquidityGross");
        assertEq(netLower, liquidityDelta, "tickLower liquidityNet");

        (uint128 grossUpper, int128 netUpper) = poolManager.getTickInfo(id, tickUpper);
        assertEq(grossUpper, uint128(int128(liquidityDelta)), "tickUpper liquidityGross");
        assertEq(netUpper, -liquidityDelta, "tickUpper liquidityNet");
    }

    /// @notice Add liquidity multiple times on the same tick range; gross and net at ticks accumulate.
    function test_modifyLiquidity_addMultipleTimes_sameTickRange_assertTickInfo() external {
        address eth = _createHTSToken("Ethereum", "ETH");
        address usdt = _createHTSToken("Tether USD", "USDT");
        (Currency t0, Currency t1) =
            eth < usdt ? (Currency.wrap(eth), Currency.wrap(usdt)) : (Currency.wrap(usdt), Currency.wrap(eth));
        PoolKey memory key = PoolKey({token0: t0, token1: t1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))});
        poolManager.initialize(key, uint160(2 ** 96));

        int24 tickLower = -60;
        int24 tickUpper = 60;
        PoolId id = key.toId();

        int128 L1 = 1000;
        int128 L2 = 500;
        int128 L3 = 300;
        int128 total = L1 + L2 + L3;

        poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                owner: signer,
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: L1,
                tickSpacing: 60,
                salt: bytes32(uint256(1))
            }),
            ""
        );
        poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                owner: signer,
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: L2,
                tickSpacing: 60,
                salt: bytes32(uint256(2))
            }),
            ""
        );
        poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                owner: signer,
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: L3,
                tickSpacing: 60,
                salt: bytes32(uint256(3))
            }),
            ""
        );

        (uint128 grossLower, int128 netLower) = poolManager.getTickInfo(id, tickLower);
        assertEq(grossLower, uint128(int128(total)), "tickLower liquidityGross after 3 adds");
        assertEq(netLower, total, "tickLower liquidityNet after 3 adds");

        (uint128 grossUpper, int128 netUpper) = poolManager.getTickInfo(id, tickUpper);
        assertEq(grossUpper, uint128(int128(total)), "tickUpper liquidityGross after 3 adds");
        assertEq(netUpper, -total, "tickUpper liquidityNet after 3 adds");
    }

    /// @notice Add liquidity at different tick ranges and assert gross/net at each tick.
    function test_modifyLiquidity_addAtDifferentTickRanges_assertEachTick() external {
        address eth = _createHTSToken("Ethereum", "ETH");
        address usdt = _createHTSToken("Tether USD", "USDT");
        (Currency t0, Currency t1) =
            eth < usdt ? (Currency.wrap(eth), Currency.wrap(usdt)) : (Currency.wrap(usdt), Currency.wrap(eth));
        PoolKey memory key = PoolKey({token0: t0, token1: t1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))});
        poolManager.initialize(key, uint160(2 ** 96));

        int128 L_A = 1000; // [-60, 60]
        int128 L_B = 600; // [-120, 0]
        int128 L_C = 400; // [0, 120]

        poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                owner: signer,
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: L_A,
                tickSpacing: 60,
                salt: bytes32(uint256(1))
            }),
            ""
        );
        poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                owner: signer,
                tickLower: -120,
                tickUpper: 0,
                liquidityDelta: L_B,
                tickSpacing: 60,
                salt: bytes32(uint256(2))
            }),
            ""
        );
        poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                owner: signer,
                tickLower: 0,
                tickUpper: 120,
                liquidityDelta: L_C,
                tickSpacing: 60,
                salt: bytes32(uint256(3))
            }),
            ""
        );

        PoolId id = key.toId();

        // Tick -120: only B lower => gross = L_B, net = +L_B
        (uint128 g_120, int128 n_120) = poolManager.getTickInfo(id, -120);
        assertEq(g_120, uint128(int128(L_B)), "tick -120 liquidityGross");
        assertEq(n_120, L_B, "tick -120 liquidityNet");

        // Tick -60: only A lower (B is [-120,0] so does not touch -60) => gross = L_A, net = L_A
        (uint128 g_60, int128 n_60) = poolManager.getTickInfo(id, -60);
        assertEq(g_60, uint128(int128(L_A)), "tick -60 liquidityGross");
        assertEq(n_60, L_A, "tick -60 liquidityNet");

        // Tick 0: B upper, C lower => gross = L_B + L_C, net = -L_B + L_C
        (uint128 g0, int128 n0) = poolManager.getTickInfo(id, 0);
        assertEq(g0, uint128(int128(L_B + L_C)), "tick 0 liquidityGross");
        assertEq(n0, -L_B + L_C, "tick 0 liquidityNet");

        // Tick 60: only A upper (C is [0,120] so upper at 120) => gross = L_A, net = -L_A
        (uint128 g60, int128 n60) = poolManager.getTickInfo(id, 60);
        assertEq(g60, uint128(int128(L_A)), "tick 60 liquidityGross");
        assertEq(n60, -L_A, "tick 60 liquidityNet");

        // Tick 120: only C upper => gross = L_C, net = -L_C
        (uint128 g120, int128 n120) = poolManager.getTickInfo(id, 120);
        assertEq(g120, uint128(int128(L_C)), "tick 120 liquidityGross");
        assertEq(n120, -L_C, "tick 120 liquidityNet");
    }

    /// @notice Demonstrates how storage slot is computed for key -> struct -> key->value:
    ///   _pools[poolId] (PoolState) -> tickBitmap[wordPos] (uint256)
    function test_storageSlot_keyStructKey_poolsTickBitmapWord() external {
        PoolKey memory key = _validPoolKey();
        poolManager.initialize(key, uint160(2 ** 96));

        int24 tickLower = -60;
        int24 tickUpper = 120;
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            owner: signer,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: 1000,
            tickSpacing: 60,
            salt: bytes32(0)
        });
        poolManager.modifyLiquidity(key, params, "");

        PoolId id = key.toId();

        // For tick -60 with tickSpacing 60: compressed = -1, wordPos = -1, bitPos = 255
        int16 wordPos = -1;
        uint256 poolsSlot = poolManager.getPoolsSlot(); // 0

        // Step 1: Base slot of PoolState for this poolId
        // slot(base of struct) = keccak256(abi.encode(poolId, poolsSlot))
        bytes32 poolIdBytes = PoolId.unwrap(id);
        uint256 basePoolSlot = uint256(keccak256(abi.encode(poolIdBytes, poolsSlot)));

        // Step 2: Slot of the tickBitmap mapping inside PoolState (offset 3: slot0=0, liquidity=1, ticks=2, tickBitmap=3)
        uint256 tickBitmapMappingSlot = basePoolSlot + 3;

        // Step 3: Slot of tickBitmap[wordPos] = keccak256(abi.encode(wordPos, tickBitmapMappingSlot))
        uint256 tickBitmapWordSlot = uint256(keccak256(abi.encode(wordPos, tickBitmapMappingSlot)));

        // Read storage directly
        uint256 valueFromStorage = uint256(vm.load(address(poolManager), bytes32(tickBitmapWordSlot)));

        // Read via the pool API
        uint256 valueFromPool = poolManager.getTickBitmapWord(id, wordPos);

        assertEq(valueFromStorage, valueFromPool, "storage slot should match pool.tickBitmap[wordPos]");
        assertTrue(valueFromPool != 0, "tickBitmap[-1] should be non-zero after adding liquidity at -60");
    }

    function test_modifyLiquidity_keyStructAndSwap() external {
        PoolKey memory key = _validPoolKey();
        poolManager.initialize(key, uint160(2 ** 96));

        int24 tickLower = 60;
        int24 tickUpper = 120;

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            owner: signer,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: 1000,
            tickSpacing: 60,
            salt: bytes32(0)
        });
        poolManager.modifyLiquidity(key, params, "");

        params = ModifyLiquidityParams({
            owner: signer, tickLower: 120, tickUpper: 180, liquidityDelta: 1000, tickSpacing: 60, salt: bytes32(0)
        });
        poolManager.modifyLiquidity(key, params, "");

        params = ModifyLiquidityParams({
            owner: signer, tickLower: -120, tickUpper: 0, liquidityDelta: 1000, tickSpacing: 60, salt: bytes32(0)
        });

        params = ModifyLiquidityParams({
            owner: signer, tickLower: -180, tickUpper: -60, liquidityDelta: 1000, tickSpacing: 60, salt: bytes32(0)
        });
        params = ModifyLiquidityParams({
            owner: signer, tickLower: -180, tickUpper: -60, liquidityDelta: 1000, tickSpacing: 60, salt: bytes32(0)
        });
        poolManager.modifyLiquidity(key, params, "");

        uint256 poolsSlot = 0;

        PoolId id = key.toId();
        bytes32 poolIdBytes = PoolId.unwrap(id);

        // uint256 basePoolSlot = uint256(keccak256(abi.encode(p)));
        uint256 basePoolSlot = uint256(keccak256(abi.encode(poolIdBytes, poolsSlot)));

        // Ticks 60 and 120 with spacing 60 → compressed 1 and 2 → both in word 0 (wordPos = compressed >> 8)
        int16 wordPos = 0;
        uint256 tickBitmapMappingSlot = basePoolSlot + 3;
        uint256 tickBitmapWordSlot = uint256(keccak256(abi.encode(wordPos, tickBitmapMappingSlot)));

        // Read storage directly
        uint256 valueFromStorage = uint256(vm.load(address(poolManager), bytes32(tickBitmapWordSlot)));

        console.log("valueFromStorage (decimal)", valueFromStorage);
        // Hex (raw bytes) - standard way to inspect storage
        console.log("valueFromStorage (hex):");
        console.logBytes(abi.encodePacked(bytes32(valueFromStorage)));
        // Base-2 (0s and 1s)
        console.log("valueFromStorage (binary):", _toBinaryString(valueFromStorage));

        // zeroForOne: price must decrease. sqrtPriceLimitX96 must be > MIN_SQRT_PRICE and < current price.
        uint160 sqrtPriceLimitX96 = TickMath.getSqrtPriceAtTick(-180);
        SwapParams memory swapParams = SwapParams({
            amountSpecified: 4000,
            tickSpacing: 60,
            zeroForOne: true,
            sqrtPriceLimitX96: sqrtPriceLimitX96,
            lpFeeOverride: 0
        });
        poolManager.swap(key, swapParams, "");
    }
}
