// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {PoolId} from "../types/PoolKey.sol";
import {Currency} from "../types/Currency.sol";
import {IHooks} from "./IHooks.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "../types/PoolOperation.sol";

interface IPoolManager {
    /// @notice Pools require tickSpacing >= MIN_TICK_SPACING (1) in #initialize to prevent underflow
    error TickSpacingTooSmall(int24 tickSpacing);
    /// @notice Pools are limited to type(int16).max tickSpacing in #initialize, to prevent overflow
    error TickSpacingTooLarge(int24 tickSpacing);
    /// @notice currency0 must be less than currency1 in pool key (strict sort order)
    error CurrenciesOutOfOrderOrEqual(address currency0, address currency1);
    /// @notice Reverts when an operation is attempted on a pool that has not been initialized
    error PoolNotInitialized();
    /// @notice tickLower must be strictly less than tickUpper
    error TicksMisordered(int24 tickLower, int24 tickUpper);
    /// @notice tickLower must be >= MIN_TICK
    error TickLowerOutOfBounds(int24 tickLower);
    /// @notice tickUpper must be <= MAX_TICK
    error TickUpperOutOfBounds(int24 tickUpper);

    /// @notice Emitted when a new pool is initialized
    /// @param id The abi encoded hash of the pool key struct for the new pool
    /// @param currency0 The first currency of the pool by address sort order
    /// @param currency1 The second currency of the pool by address sort order
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param tickSpacing The minimum number of ticks between initialized ticks
    /// @param hooks The hooks contract address for the pool, or address(0) if none
    /// @param sqrtPriceX96 The price of the pool on initialization
    /// @param tick The initial tick of the pool corresponding to the initialized price
    event Initialize(
        PoolId indexed id,
        Currency indexed currency0,
        Currency indexed currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks,
        uint160 sqrtPriceX96,
        int24 tick
    );

    /// @notice Emitted when liquidity is modified in a pool
    /// @param id The pool ID
    /// @param sender The address that modified liquidity
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param liquidityDelta The change in liquidity (positive for add, negative for remove)
    /// @param salt The salt used to derive the position ID
    event ModifyLiquidity(
        PoolId indexed id, address indexed sender, int24 tickLower, int24 tickUpper, int128 liquidityDelta, bytes32 salt
    );

    /// @notice Initialize the state for a given pool ID
    /// @dev A swap fee totaling MAX_SWAP_FEE (100%) makes exact output swaps impossible since the input is entirely consumed by the fee
    /// @param key The pool key for the pool to initialize
    /// @param sqrtPriceX96 The initial square root price
    /// @return tick The initial tick of the pool
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);

    /// @notice Modify liquidity in a pool
    /// @param key The pool key
    /// @param params The modify liquidity parameters (tickLower, tickUpper, liquidityDelta, salt)
    /// @param hookData Optional data to pass to the pool's hooks
    /// @return callerDelta The balance delta for the caller (amounts to settle)
    /// @return feesAccrued The fees accrued to the position
    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta callerDelta, BalanceDelta feesAccrued);
}
