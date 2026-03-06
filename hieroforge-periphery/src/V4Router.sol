// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
import {IV4Router} from "./interfaces/IV4Router.sol";

/// @title V4Router
/// @notice Router for swapping tokens via hieroforge-core PoolManager (HieroForge periphery)
/// @dev Extends IV4Router; methods and implementation will be added gradually
abstract contract V4Router is IV4Router {
    IPoolManager public immutable poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @notice Returns the address to use as "caller" for settle/take (e.g. in unlock callback)
    /// @dev Override in UniversalRouter to return the execute() initiator when inside a callback
    function msgSender() public view virtual returns (address) {
        return msg.sender;
    }

    /// @notice Runs the v4 swap payload (e.g. poolManager.unlock). Override in a concrete router.
    /// @param input ABI-encoded data for the swap (e.g. unlock calldata)
    function _executeV4Swap(bytes calldata input) internal virtual {
        input; // silence unused
        revert("V4_SWAP not implemented");
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Swap methods (stubs — implement gradually)
    // ─────────────────────────────────────────────────────────────────────────────

    // function swapExactInputSingle(ExactInputSingleParams calldata params) external virtual returns (uint128 amountOut);
    // function swapExactOutputSingle(ExactOutputSingleParams calldata params) external virtual returns (uint128 amountIn);
}
