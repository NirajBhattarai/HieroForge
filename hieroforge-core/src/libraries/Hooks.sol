// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {IHooks} from "../interfaces/IHooks.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams} from "../types/ModifyLiquidityParams.sol";
import {SwapParams} from "../types/SwapParams.sol";
import {CustomRevert} from "./CustomRevert.sol";

/// @title Hooks
/// @notice Library for hook address validation and invocation.
/// @dev Hook permissions are encoded in the lower 6 bits of the hook contract address.
///      Adapted for Hedera — no EIP-712 permit dependency.
library Hooks {
    using CustomRevert for bytes4;

    /// @notice Thrown when a hook returns an unexpected selector
    error InvalidHookResponse();

    /// @notice Thrown when a hook address has permission flags but no code
    error HookAddressNotValid(address hooks);

    // Permission bit flags — encoded in the lower 6 bits of the hook address
    uint160 internal constant BEFORE_INITIALIZE_FLAG = 1 << 0;
    uint160 internal constant AFTER_INITIALIZE_FLAG = 1 << 1;
    uint160 internal constant BEFORE_MODIFY_LIQUIDITY_FLAG = 1 << 2;
    uint160 internal constant AFTER_MODIFY_LIQUIDITY_FLAG = 1 << 3;
    uint160 internal constant BEFORE_SWAP_FLAG = 1 << 4;
    uint160 internal constant AFTER_SWAP_FLAG = 1 << 5;

    /// @dev All permission bits combined
    uint160 internal constant ALL_HOOK_MASK = (1 << 6) - 1; // lower 6 bits

    struct Permissions {
        bool beforeInitialize;
        bool afterInitialize;
        bool beforeModifyLiquidity;
        bool afterModifyLiquidity;
        bool beforeSwap;
        bool afterSwap;
    }

    /// @notice Check if the hook address has the given permission flag set
    function hasPermission(address hookAddress, uint160 flag) internal pure returns (bool) {
        return uint160(hookAddress) & flag != 0;
    }

    /// @notice Returns true if the hook address is valid (address(0) or has code when flags set)
    function isValidHookAddress(address hookAddress) internal view returns (bool) {
        if (hookAddress == address(0)) return true;

        uint160 flags = uint160(hookAddress) & ALL_HOOK_MASK;
        if (flags != 0) {
            uint256 codeSize;
            assembly ("memory-safe") {
                codeSize := extcodesize(hookAddress)
            }
            return codeSize > 0;
        }
        return true;
    }

    /// @notice Validate that a hook address is consistent (has code if permissions are set)
    function validateHookPermissions(address hookAddress) internal view {
        if (!isValidHookAddress(hookAddress)) {
            revert HookAddressNotValid(hookAddress);
        }
    }

    // ─── Hook invocation helpers ───────────────────────────────────────────

    function callBeforeInitialize(
        address hooks,
        address sender,
        PoolKey memory key,
        uint160 sqrtPriceX96,
        bytes calldata hookData
    ) internal {
        if (!hasPermission(hooks, BEFORE_INITIALIZE_FLAG)) return;
        bytes4 result = IHooks(hooks).beforeInitialize(sender, key, sqrtPriceX96, hookData);
        if (result != IHooks.beforeInitialize.selector) InvalidHookResponse.selector.revertWith();
    }

    function callAfterInitialize(
        address hooks,
        address sender,
        PoolKey memory key,
        uint160 sqrtPriceX96,
        int24 tick,
        bytes calldata hookData
    ) internal {
        if (!hasPermission(hooks, AFTER_INITIALIZE_FLAG)) return;
        bytes4 result = IHooks(hooks).afterInitialize(sender, key, sqrtPriceX96, tick, hookData);
        if (result != IHooks.afterInitialize.selector) InvalidHookResponse.selector.revertWith();
    }

    function callBeforeModifyLiquidity(
        address hooks,
        address sender,
        PoolKey memory key,
        ModifyLiquidityParams memory params,
        bytes calldata hookData
    ) internal {
        if (!hasPermission(hooks, BEFORE_MODIFY_LIQUIDITY_FLAG)) return;
        bytes4 result = IHooks(hooks).beforeModifyLiquidity(sender, key, params, hookData);
        if (result != IHooks.beforeModifyLiquidity.selector) InvalidHookResponse.selector.revertWith();
    }

    function callAfterModifyLiquidity(
        address hooks,
        address sender,
        PoolKey memory key,
        ModifyLiquidityParams memory params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) internal {
        if (!hasPermission(hooks, AFTER_MODIFY_LIQUIDITY_FLAG)) return;
        bytes4 result = IHooks(hooks).afterModifyLiquidity(sender, key, params, delta, feesAccrued, hookData);
        if (result != IHooks.afterModifyLiquidity.selector) InvalidHookResponse.selector.revertWith();
    }

    function callBeforeSwap(
        address hooks,
        address sender,
        PoolKey memory key,
        SwapParams memory params,
        bytes calldata hookData
    ) internal returns (BeforeSwapDelta beforeSwapDelta, uint24 lpFeeOverride) {
        if (!hasPermission(hooks, BEFORE_SWAP_FLAG)) {
            return (BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        bytes4 result;
        (result, beforeSwapDelta, lpFeeOverride) = IHooks(hooks).beforeSwap(sender, key, params, hookData);
        if (result != IHooks.beforeSwap.selector) InvalidHookResponse.selector.revertWith();
    }

    function callAfterSwap(
        address hooks,
        address sender,
        PoolKey memory key,
        SwapParams memory params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal returns (int128 hookDeltaUnspecified) {
        if (!hasPermission(hooks, AFTER_SWAP_FLAG)) return 0;
        bytes4 result;
        (result, hookDeltaUnspecified) = IHooks(hooks).afterSwap(sender, key, params, delta, hookData);
        if (result != IHooks.afterSwap.selector) InvalidHookResponse.selector.revertWith();
    }
}
