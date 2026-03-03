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
import {IERC20} from "hedera-forking/IERC20.sol";

/// @notice Tests for PoolManager.modifyLiquidity (Uniswap v4-style setup)
contract PoolManagerModifyLiquidityTest is Test, Deployers {
    function setUp() public {
        // HTS tokens (hedera-forking at 0x167). Run with --ffi
        initializeManagerRoutersAndPools();
        // Set owner on default liquidity params to the router so position is attributed correctly
        LIQUIDITY_PARAMS.owner = address(modifyLiquidityRouter);
        REMOVE_LIQUIDITY_PARAMS.owner = address(modifyLiquidityRouter);
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
            owner: address(modifyLiquidityRouter),
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 1e18,
            tickSpacing: 60,
            salt: bytes32(0)
        });

        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        modifyLiquidityRouter.modifyLiquidity(uninitializedKey, params, ZERO_BYTES);
    }

    /// @notice modifyLiquidity reverts when key has unsorted currencies (key.validate() at line 67)
    function test_modifyLiquidity_revertsWhenKey_unsortedCurrencies() public {
        PoolKey memory badKey = PoolKey({
            currency0: currency1,
            currency1: currency0,
            fee: key.fee,
            tickSpacing: key.tickSpacing,
            hooks: key.hooks
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

    /// @notice Add liquidity via router: HTS tokens are transferred to the manager (actual settle flow)
    function test_addLiquidity_succeedsWithHtsTransfer() public {
        // HTS tokens are created with initialTotalSupply 10e9 raw units; use small liquidity so amounts fit
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            owner: address(modifyLiquidityRouter),
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 1000, // small L so token amounts are small
            tickSpacing: 60,
            salt: bytes32(0)
        });

        // Router must hold tokens to settle; this contract is the HTS treasury so we fund the router
        uint256 fundAmount = 5e9; // half of 10e9 initial supply per token
        require(IERC20(Currency.unwrap(currency0)).transfer(address(modifyLiquidityRouter), fundAmount), "transfer0");
        require(IERC20(Currency.unwrap(currency1)).transfer(address(modifyLiquidityRouter), fundAmount), "transfer1");

        uint256 managerBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(address(manager));
        uint256 managerBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(address(manager));

        (BalanceDelta delta,) =
            modifyLiquidityRouter.modifyLiquidity(key, params, ZERO_BYTES);

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
}
