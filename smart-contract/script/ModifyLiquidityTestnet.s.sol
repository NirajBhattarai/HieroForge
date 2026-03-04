// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {htsSetup} from "hedera-forking/htsSetup.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {ModifyLiquidityRouter} from "../src/ModifyLiquidityRouter.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {ModifyLiquidityParams} from "../src/types/ModifyLiquidityParams.sol";
import {Currency} from "../src/types/Currency.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {IERC20Minimal} from "../src/interfaces/IERC20Minimal.sol";

/// @notice Initialize pool (if not already) and add or remove liquidity on testnet via ModifyLiquidityRouter.
/// If the pool is not initialized, initializes it at 1:1 price before adding liquidity.
///
/// Required env:
///   PRIVATE_KEY          - deployer key
///   POOL_MANAGER_ADDRESS - PoolManager contract
///   ROUTER_ADDRESS       - ModifyLiquidityRouter contract
///   CURRENCY0_ADDRESS    - token0 address (lower address)
///   CURRENCY1_ADDRESS    - token1 address (higher address)
///
/// Optional env (defaults shown):
///   FEE (3000), TICK_SPACING (60), TICK_LOWER (-120), TICK_UPPER (120),
///   LIQUIDITY_DELTA (default 1e8; use 1e18 only if AMOUNT0/AMOUNT1 are ~6e15+ each, else "insufficient balance"), SALT (0)
///   AMOUNT0, AMOUNT1 - in token base units; script transfers these to the router. Must cover what modifyLiquidity needs for the chosen LIQUIDITY_DELTA.
///
/// Usage: run with --ffi (for htsSetup) and --skip-simulation when using HTS tokens (currency addresses at 0x167).
///   forge script script/ModifyLiquidityTestnet.s.sol:ModifyLiquidityTestnetScript \
///     --rpc-url https://testnet.hashio.io/api --broadcast --private-key $PRIVATE_KEY --ffi --skip-simulation
contract ModifyLiquidityTestnetScript is Script {
    /// @dev sqrt(1/1) * 2^96 = 1:1 price (same as CreatePoolAndAddLiquidityTestnet)
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function run() external {
        // HTS emulation at 0x167 so token transfers (HTS tokens) don't hit InvalidFEOpcode during script run
        htsSetup();

        uint256 PRIVATE_KEY = vm.envUint("PRIVATE_KEY");

        address managerAddr = vm.envAddress("POOL_MANAGER_ADDRESS");
        address routerAddr = vm.envAddress("ROUTER_ADDRESS");
        address c0 = vm.envAddress("CURRENCY0_ADDRESS");
        address c1 = vm.envAddress("CURRENCY1_ADDRESS");

        (Currency currency0, Currency currency1) =
            c0 < c1 ? (Currency.wrap(c0), Currency.wrap(c1)) : (Currency.wrap(c1), Currency.wrap(c0));

        uint24 fee = uint24(vm.envOr("FEE", uint256(3000)));
        int24 tickSpacing = int24(uint24(vm.envOr("TICK_SPACING", uint256(60))));
        int24 tickLower = int24(vm.envOr("TICK_LOWER", int256(-120)));
        int24 tickUpper = int24(vm.envOr("TICK_UPPER", int256(120)));
        // Default 1e8: with AMOUNT0=AMOUNT1=1e6 the router has enough. For 1e18 liquidity at 1:1 (-120..120) need ~6e15 per token.
        int128 liquidityDelta = int128(vm.envOr("LIQUIDITY_DELTA", int256(1e8)));
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        uint256 amount0 = vm.envOr("AMOUNT0", uint256(0));
        uint256 amount1 = vm.envOr("AMOUNT1", uint256(0));

        IPoolManager manager = IPoolManager(managerAddr);
        ModifyLiquidityRouter router = ModifyLiquidityRouter(payable(routerAddr));

        PoolKey memory key = PoolKey({
            currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: address(0)
        });

        vm.startBroadcast(PRIVATE_KEY);

        // 1. Initialize pool at 1:1 if not already initialized (reverts with PoolAlreadyInitialized if already done)
        try manager.initialize(key, SQRT_PRICE_1_1) returns (int24 tick) {
            console.log("Pool initialized at 1:1 price, initial tick:", tick);
        } catch (bytes memory) {
            // Pool already initialized or other error; continue to add liquidity
        }

        // 2. Optional: fund router so it can settle (router must hold tokens when adding liquidity)
        if (amount0 > 0 && Currency.unwrap(currency0) != address(0)) {
            require(
                IERC20Minimal(Currency.unwrap(currency0)).transfer(routerAddr, amount0),
                "ModifyLiquidityTestnet: transfer token0 failed"
            );
            console.log("Transferred token0 to router:", amount0);
        }
        if (amount1 > 0 && Currency.unwrap(currency1) != address(0)) {
            require(
                IERC20Minimal(Currency.unwrap(currency1)).transfer(routerAddr, amount1),
                "ModifyLiquidityTestnet: transfer token1 failed"
            );
            console.log("Transferred token1 to router:", amount1);
        }

        // 3. Add or remove liquidity
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            owner: routerAddr,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: liquidityDelta,
            tickSpacing: tickSpacing,
            salt: salt
        });

        (BalanceDelta callerDelta, BalanceDelta feesAccrued) = router.modifyLiquidity(key, params, "");

        vm.stopBroadcast();

        console.log("ModifyLiquidity amount0:", callerDelta.amount0());
        console.log("ModifyLiquidity amount1:", callerDelta.amount1());
        console.log("Fees accrued amount0:", feesAccrued.amount0());
        console.log("Fees accrued amount1:", feesAccrued.amount1());
    }
}
