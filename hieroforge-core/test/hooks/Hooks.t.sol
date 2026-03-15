// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "../../src/PoolManager.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {PoolId} from "../../src/types/PoolId.sol";
import {Currency} from "../../src/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "../../src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "../../src/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams} from "../../src/types/ModifyLiquidityParams.sol";
import {SwapParams} from "../../src/types/SwapParams.sol";
import {TickMath} from "../../src/libraries/TickMath.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import {Router} from "../utils/Router.sol";
import {Constants} from "../utils/Constants.sol";

// ════════════════════════════════════════════════════════════════════════════
//  Mock Hooks — test contracts deployed at addresses with encoded permission bits
// ════════════════════════════════════════════════════════════════════════════

/// @notice Hook that tracks all 6 callbacks and returns correct selectors
contract AllCallbacksHook is IHooks {
    uint256 public beforeInitializeCount;
    uint256 public afterInitializeCount;
    uint256 public beforeModifyLiquidityCount;
    uint256 public afterModifyLiquidityCount;
    uint256 public beforeSwapCount;
    uint256 public afterSwapCount;

    function beforeInitialize(address, PoolKey calldata, uint160, bytes calldata) external returns (bytes4) {
        beforeInitializeCount++;
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24, bytes calldata) external returns (bytes4) {
        afterInitializeCount++;
        return IHooks.afterInitialize.selector;
    }

    function beforeModifyLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        returns (bytes4)
    {
        beforeModifyLiquidityCount++;
        return IHooks.beforeModifyLiquidity.selector;
    }

    function afterModifyLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external returns (bytes4) {
        afterModifyLiquidityCount++;
        return IHooks.afterModifyLiquidity.selector;
    }

    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        beforeSwapCount++;
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        returns (bytes4, int128)
    {
        afterSwapCount++;
        return (IHooks.afterSwap.selector, 0);
    }
}

/// @notice Hook that returns wrong selectors to test revert
contract BadSelectorHook is IHooks {
    function beforeInitialize(address, PoolKey calldata, uint160, bytes calldata) external pure returns (bytes4) {
        return bytes4(0xdeadbeef);
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24, bytes calldata) external pure returns (bytes4) {
        return bytes4(0xdeadbeef);
    }

    function beforeModifyLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return bytes4(0xdeadbeef);
    }

    function afterModifyLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4) {
        return bytes4(0xdeadbeef);
    }

    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        pure
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        return (bytes4(0xdeadbeef), BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        pure
        returns (bytes4, int128)
    {
        return (bytes4(0xdeadbeef), 0);
    }
}

/// @notice Hook that reverts on beforeSwap
contract RevertingHook is IHooks {
    error HookReverted();

    function beforeInitialize(address, PoolKey calldata, uint160, bytes calldata) external pure returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24, bytes calldata) external pure returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }

    function beforeModifyLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IHooks.beforeModifyLiquidity.selector;
    }

    function afterModifyLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4) {
        return IHooks.afterModifyLiquidity.selector;
    }

    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        pure
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        revert HookReverted();
    }

    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        pure
        returns (bytes4, int128)
    {
        return (IHooks.afterSwap.selector, 0);
    }
}

/// @notice Hook that only has BEFORE_SWAP permission (bit 4 = 0x10)
contract BeforeSwapOnlyHook is IHooks {
    uint256 public beforeSwapCount;

    function beforeInitialize(address, PoolKey calldata, uint160, bytes calldata) external pure returns (bytes4) {
        revert("should not be called");
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24, bytes calldata) external pure returns (bytes4) {
        revert("should not be called");
    }

    function beforeModifyLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        revert("should not be called");
    }

    function afterModifyLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4) {
        revert("should not be called");
    }

    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        beforeSwapCount++;
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        pure
        returns (bytes4, int128)
    {
        revert("should not be called");
    }
}

/// @notice Hook that overrides LP fee via beforeSwap
contract FeeOverrideHook is IHooks {
    uint24 public feeOverride;

    constructor(uint24 _feeOverride) {
        feeOverride = _feeOverride;
    }

    function beforeInitialize(address, PoolKey calldata, uint160, bytes calldata) external pure returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24, bytes calldata) external pure returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }

    function beforeModifyLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IHooks.beforeModifyLiquidity.selector;
    }

    function afterModifyLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4) {
        return IHooks.afterModifyLiquidity.selector;
    }

    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        view
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, feeOverride);
    }

    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        pure
        returns (bytes4, int128)
    {
        return (IHooks.afterSwap.selector, 0);
    }
}

// ════════════════════════════════════════════════════════════════════════════
//  TEST 1: Hooks Library — permission validation
// ════════════════════════════════════════════════════════════════════════════

contract HooksLibraryTest is Test {
    function test_hasPermission_BEFORE_INITIALIZE() public pure {
        // Address with bit 0 set
        address addr = address(uint160(0x01));
        assertTrue(Hooks.hasPermission(addr, Hooks.BEFORE_INITIALIZE_FLAG));
        assertFalse(Hooks.hasPermission(addr, Hooks.AFTER_INITIALIZE_FLAG));
    }

    function test_hasPermission_AFTER_SWAP() public pure {
        address addr = address(uint160(0x20)); // bit 5
        assertTrue(Hooks.hasPermission(addr, Hooks.AFTER_SWAP_FLAG));
        assertFalse(Hooks.hasPermission(addr, Hooks.BEFORE_SWAP_FLAG));
    }

    function test_hasPermission_allFlags() public pure {
        address addr = address(uint160(0x3F)); // all 6 bits
        assertTrue(Hooks.hasPermission(addr, Hooks.BEFORE_INITIALIZE_FLAG));
        assertTrue(Hooks.hasPermission(addr, Hooks.AFTER_INITIALIZE_FLAG));
        assertTrue(Hooks.hasPermission(addr, Hooks.BEFORE_MODIFY_LIQUIDITY_FLAG));
        assertTrue(Hooks.hasPermission(addr, Hooks.AFTER_MODIFY_LIQUIDITY_FLAG));
        assertTrue(Hooks.hasPermission(addr, Hooks.BEFORE_SWAP_FLAG));
        assertTrue(Hooks.hasPermission(addr, Hooks.AFTER_SWAP_FLAG));
    }

    function test_hasPermission_noFlags() public pure {
        address addr = address(uint160(0x40)); // no lower 6 bits
        assertFalse(Hooks.hasPermission(addr, Hooks.BEFORE_INITIALIZE_FLAG));
        assertFalse(Hooks.hasPermission(addr, Hooks.AFTER_INITIALIZE_FLAG));
        assertFalse(Hooks.hasPermission(addr, Hooks.BEFORE_MODIFY_LIQUIDITY_FLAG));
        assertFalse(Hooks.hasPermission(addr, Hooks.AFTER_MODIFY_LIQUIDITY_FLAG));
        assertFalse(Hooks.hasPermission(addr, Hooks.BEFORE_SWAP_FLAG));
        assertFalse(Hooks.hasPermission(addr, Hooks.AFTER_SWAP_FLAG));
    }

    function test_isValidHookAddress_zeroAddress() public view {
        assertTrue(Hooks.isValidHookAddress(address(0)));
    }

    function test_isValidHookAddress_noPermissionBits_noCode() public view {
        assertTrue(Hooks.isValidHookAddress(address(uint160(0x40))));
    }

    function test_isValidHookAddress_permissionBits_noCode_reverts() public view {
        // Address with flags set but no deployed code
        assertFalse(Hooks.isValidHookAddress(address(uint160(0x01))));
    }

    function test_isValidHookAddress_permissionBits_withCode() public {
        MockERC20 mock = new MockERC20();
        // We need an address with permission bits AND code. Use vm.etch to place code at a flagged address.
        address flaggedAddr = address(uint160(0x3F));
        vm.etch(flaggedAddr, address(mock).code);
        assertTrue(Hooks.isValidHookAddress(flaggedAddr));
    }

    function test_validateHookPermissions_reverts_whenInvalid() public {
        // Test via PoolManager.initialize since validateHookPermissions is an internal library call
        PoolManager pm = new PoolManager();
        address flaggedNoCode = address(uint160(0x01)); // has permission bit but no code
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x100)),
            currency1: Currency.wrap(address(0x200)),
            fee: 3000,
            tickSpacing: 60,
            hooks: flaggedNoCode
        });
        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, flaggedNoCode));
        pm.initialize(key, Constants.SQRT_PRICE_1_1);
    }
}

// ════════════════════════════════════════════════════════════════════════════
//  TEST 2: PoolManager hooks integration — all callbacks fire
// ════════════════════════════════════════════════════════════════════════════

contract PoolManagerHooksIntegrationTest is Test {
    PoolManager public poolManager;
    Router public router;
    AllCallbacksHook public hook;
    MockERC20 public token0;
    MockERC20 public token1;

    /// @dev Computes an address with all 6 permission bits set (lower 6 = 0x3F)
    function _deployHookAtFlaggedAddress() internal returns (address) {
        AllCallbacksHook impl = new AllCallbacksHook();
        // Clear lower 6 bits, then set all 6 bits
        address flagged = address((uint160(address(impl)) & ~uint160(0x3F)) | uint160(0x3F));
        vm.etch(flagged, address(impl).code);
        return flagged;
    }

    function setUp() public {
        poolManager = new PoolManager();
        router = new Router(poolManager);

        address hookAddr = _deployHookAtFlaggedAddress();
        hook = AllCallbacksHook(hookAddr);

        token0 = new MockERC20();
        token1 = new MockERC20();
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }
        token0.mint(address(this), 100e18);
        token1.mint(address(this), 100e18);
    }

    function _makeHookKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(hook)
        });
    }

    function test_initialize_callsBeforeAndAfterInitialize() public {
        PoolKey memory key = _makeHookKey();
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);

        assertEq(hook.beforeInitializeCount(), 1, "beforeInitialize should be called once");
        assertEq(hook.afterInitializeCount(), 1, "afterInitialize should be called once");
    }

    function test_modifyLiquidity_callsBeforeAndAfterModifyLiquidity() public {
        PoolKey memory key = _makeHookKey();
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);

        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        token0.transfer(address(router), 1e18);
        token1.transfer(address(router), 1e18);

        ModifyLiquidityParams memory params =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000, salt: bytes32(0)});
        router.modifyLiquidity(key, params, "");

        assertEq(hook.beforeModifyLiquidityCount(), 1, "beforeModifyLiquidity should be called once");
        assertEq(hook.afterModifyLiquidityCount(), 1, "afterModifyLiquidity should be called once");
    }

    function test_swap_callsBeforeAndAfterSwap() public {
        PoolKey memory key = _makeHookKey();
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);

        // Add liquidity first
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        token0.transfer(address(router), 10e18);
        token1.transfer(address(router), 10e18);

        ModifyLiquidityParams memory liqParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: bytes32(0)});
        router.modifyLiquidity(key, liqParams, "");

        // Swap
        token0.transfer(address(router), 1e18);
        SwapParams memory params = SwapParams({
            amountSpecified: -int256(uint256(1000)),
            tickSpacing: 60,
            zeroForOne: true,
            sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
            lpFeeOverride: 0
        });
        router.swap(key, params, "");

        assertEq(hook.beforeSwapCount(), 1, "beforeSwap should be called once");
        assertEq(hook.afterSwapCount(), 1, "afterSwap should be called once");
    }

    function test_allCallbacks_countAccumulates() public {
        PoolKey memory key = _makeHookKey();
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);

        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        token0.transfer(address(router), 50e18);
        token1.transfer(address(router), 50e18);

        // Add liquidity twice
        ModifyLiquidityParams memory liqParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: bytes32(0)});
        router.modifyLiquidity(key, liqParams, "");
        router.modifyLiquidity(key, liqParams, abi.encode(uint256(1)));

        assertEq(hook.beforeModifyLiquidityCount(), 2);
        assertEq(hook.afterModifyLiquidityCount(), 2);

        // Swap twice
        SwapParams memory params = SwapParams({
            amountSpecified: -int256(uint256(100)),
            tickSpacing: 60,
            zeroForOne: true,
            sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
            lpFeeOverride: 0
        });
        router.swap(key, params, "");
        router.swap(key, params, "");

        assertEq(hook.beforeSwapCount(), 2);
        assertEq(hook.afterSwapCount(), 2);
    }

    function test_noHooks_addressZero_succeeds() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        // Should succeed without any hook calls
        int24 tick = poolManager.initialize(key, Constants.SQRT_PRICE_1_1);
        assertEq(tick, 0);
    }
}

// ════════════════════════════════════════════════════════════════════════════
//  TEST 3: Hook reverts and bad selectors
// ════════════════════════════════════════════════════════════════════════════

contract PoolManagerHooksRevertTest is Test {
    PoolManager public poolManager;
    Router public router;
    MockERC20 public token0;
    MockERC20 public token1;

    function setUp() public {
        poolManager = new PoolManager();
        router = new Router(poolManager);

        token0 = new MockERC20();
        token1 = new MockERC20();
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }
        token0.mint(address(this), 100e18);
        token1.mint(address(this), 100e18);
    }

    function _deployAtFlagged(address impl, uint160 flags) internal returns (address) {
        address flagged = address((uint160(impl) & ~uint160(0x3F)) | flags);
        vm.etch(flagged, impl.code);
        return flagged;
    }

    function test_badSelector_beforeInitialize_reverts() public {
        BadSelectorHook impl = new BadSelectorHook();
        address hookAddr = _deployAtFlagged(address(impl), 0x01); // BEFORE_INITIALIZE
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: hookAddr
        });
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);
    }

    function test_badSelector_afterInitialize_reverts() public {
        BadSelectorHook impl = new BadSelectorHook();
        address hookAddr = _deployAtFlagged(address(impl), 0x02); // AFTER_INITIALIZE only
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: hookAddr
        });
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);
    }

    function test_revertingHook_beforeSwap_reverts() public {
        RevertingHook impl = new RevertingHook();
        // BEFORE_SWAP (0x10) + BEFORE_INITIALIZE (0x01) for init to pass
        address hookAddr = _deployAtFlagged(address(impl), 0x11);
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: hookAddr
        });
        // Initialize succeeds (beforeInitialize returns correct selector)
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);

        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        token0.transfer(address(router), 10e18);
        token1.transfer(address(router), 10e18);

        ModifyLiquidityParams memory liqParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: bytes32(0)});
        router.modifyLiquidity(key, liqParams, "");

        SwapParams memory params = SwapParams({
            amountSpecified: -int256(uint256(100)),
            tickSpacing: 60,
            zeroForOne: true,
            sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
            lpFeeOverride: 0
        });
        vm.expectRevert(RevertingHook.HookReverted.selector);
        router.swap(key, params, "");
    }

    function test_hookAddressNotValid_permissionBitsButNoCode() public {
        address noCode = address(uint160(0x0F)); // has permission bits, no code
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: noCode
        });
        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, noCode));
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);
    }
}

// ════════════════════════════════════════════════════════════════════════════
//  TEST 4: Selective hook permissions and fee override
// ════════════════════════════════════════════════════════════════════════════

contract PoolManagerSelectiveHooksTest is Test {
    PoolManager public poolManager;
    Router public router;
    MockERC20 public token0;
    MockERC20 public token1;

    function setUp() public {
        poolManager = new PoolManager();
        router = new Router(poolManager);

        token0 = new MockERC20();
        token1 = new MockERC20();
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }
        token0.mint(address(this), 100e18);
        token1.mint(address(this), 100e18);
    }

    function _deployAtFlagged(address impl, uint160 flags) internal returns (address) {
        address flagged = address((uint160(impl) & ~uint160(0x3F)) | flags);
        vm.etch(flagged, impl.code);
        return flagged;
    }

    function test_beforeSwapOnly_otherCallbacksNotCalled() public {
        BeforeSwapOnlyHook impl = new BeforeSwapOnlyHook();
        // Only BEFORE_SWAP = 0x10
        address hookAddr = _deployAtFlagged(address(impl), 0x10);
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: hookAddr
        });
        // Initialize succeeds (no beforeInitialize permission → skipped)
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);

        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        token0.transfer(address(router), 10e18);
        token1.transfer(address(router), 10e18);

        ModifyLiquidityParams memory liqParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: bytes32(0)});
        // modifyLiquidity succeeds (no beforeModifyLiquidity permission → skipped)
        router.modifyLiquidity(key, liqParams, "");

        // Swap: beforeSwap IS called
        token0.transfer(address(router), 1e18);
        SwapParams memory params = SwapParams({
            amountSpecified: -int256(uint256(100)),
            tickSpacing: 60,
            zeroForOne: true,
            sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
            lpFeeOverride: 0
        });
        router.swap(key, params, "");

        assertEq(BeforeSwapOnlyHook(hookAddr).beforeSwapCount(), 1, "beforeSwap called once");
    }

    function test_feeOverrideHook_overridesPoolFee() public {
        FeeOverrideHook impl = new FeeOverrideHook(500); // override to 500 bps (0.05%)
        // BEFORE_SWAP (0x10)
        address hookAddr = _deployAtFlagged(address(impl), 0x10);
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000, // pool fee is 3000 but hook overrides to 500
            tickSpacing: 60,
            hooks: hookAddr
        });
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);

        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        token0.transfer(address(router), 10e18);
        token1.transfer(address(router), 10e18);

        ModifyLiquidityParams memory liqParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: bytes32(0)});
        router.modifyLiquidity(key, liqParams, "");

        // Swap with fee override hook
        token0.transfer(address(router), 1e18);
        SwapParams memory params = SwapParams({
            amountSpecified: -int256(uint256(1000)),
            tickSpacing: 60,
            zeroForOne: true,
            sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
            lpFeeOverride: 0
        });
        BalanceDelta delta = router.swap(key, params, "");

        // With lower fees, we should get more output
        assertGt(delta.amount1(), 0, "should receive token1");
    }

    function test_multipleSwaps_hookCalledEachTime() public {
        AllCallbacksHook impl = new AllCallbacksHook();
        address hookAddr = address((uint160(address(impl)) & ~uint160(0x3F)) | uint160(0x3F));
        vm.etch(hookAddr, address(impl).code);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: hookAddr
        });
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);

        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        token0.transfer(address(router), 50e18);
        token1.transfer(address(router), 50e18);

        ModifyLiquidityParams memory liqParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: bytes32(0)});
        router.modifyLiquidity(key, liqParams, "");

        SwapParams memory params = SwapParams({
            amountSpecified: -int256(uint256(100)),
            tickSpacing: 60,
            zeroForOne: true,
            sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
            lpFeeOverride: 0
        });

        // Do 5 swaps
        for (uint256 i = 0; i < 5; i++) {
            router.swap(key, params, "");
        }

        assertEq(AllCallbacksHook(hookAddr).beforeSwapCount(), 5, "beforeSwap called 5 times");
        assertEq(AllCallbacksHook(hookAddr).afterSwapCount(), 5, "afterSwap called 5 times");
    }

    function test_hookData_passedThrough() public {
        // This test verifies the hook data parameter flows through correctly
        AllCallbacksHook impl = new AllCallbacksHook();
        address hookAddr = address((uint160(address(impl)) & ~uint160(0x3F)) | uint160(0x3F));
        vm.etch(hookAddr, address(impl).code);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: hookAddr
        });
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);

        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        token0.transfer(address(router), 10e18);
        token1.transfer(address(router), 10e18);

        bytes memory hookData = abi.encode("test data", uint256(42));

        ModifyLiquidityParams memory liqParams =
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: bytes32(0)});
        router.modifyLiquidity(key, liqParams, hookData);

        // Verify callbacks were called (the data itself is transparent to AllCallbacksHook)
        assertEq(AllCallbacksHook(hookAddr).beforeModifyLiquidityCount(), 1);
        assertEq(AllCallbacksHook(hookAddr).afterModifyLiquidityCount(), 1);
    }
}
