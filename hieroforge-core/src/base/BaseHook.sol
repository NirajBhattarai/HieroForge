// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams} from "../types/ModifyLiquidityParams.sol";
import {SwapParams} from "../types/SwapParams.sol";
import {Hooks} from "../libraries/Hooks.sol";

/// @title BaseHook
/// @notice Abstract base contract for building Uniswap v4-style hooks on Hedera.
/// @dev Override only the callbacks your hook needs. Default implementations revert with HookNotImplemented.
///      No EIP-712 permit dependency — access control is via onlyPoolManager modifier.
abstract contract BaseHook is IHooks {
    error HookNotImplemented();
    error NotPoolManager();

    IPoolManager public immutable poolManager;

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @notice Override to declare which hook callbacks this contract implements.
    function getHookPermissions() public pure virtual returns (Hooks.Permissions memory);

    // ─── Default implementations (revert if not overridden) ────────────────

    function beforeInitialize(address, PoolKey calldata, uint160, bytes calldata)
        external
        virtual
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24, bytes calldata)
        external
        virtual
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function beforeModifyLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        virtual
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterModifyLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external virtual override returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        virtual
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        revert HookNotImplemented();
    }

    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        virtual
        override
        returns (bytes4, int128)
    {
        revert HookNotImplemented();
    }
}
