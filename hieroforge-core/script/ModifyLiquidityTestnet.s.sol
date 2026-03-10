// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {htsSetup} from "hedera-forking/htsSetup.sol";
import {Router} from "../test/utils/Router.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {ModifyLiquidityParams} from "../src/types/ModifyLiquidityParams.sol";
import {Currency} from "../src/types/Currency.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {IERC20Minimal} from "../src/interfaces/IERC20Minimal.sol";

/// @notice Add liquidity only on testnet via Router. Does not initialize the pool.
/// Funds the router with AMOUNT0/AMOUNT1 then adds liquidity in multiple tick ranges (positions).
///
/// Required env:
///   PRIVATE_KEY          - deployer key
///   POOL_MANAGER_ADDRESS - PoolManager contract
///   ROUTER_ADDRESS       - Router contract
///   CURRENCY0_ADDRESS    - token0 address (lower address)
///   CURRENCY1_ADDRESS    - token1 address (higher address)
///
/// Optional env (defaults shown):
///   FEE (3000), TICK_SPACING (60),
///   LIQUIDITY_DELTA (default 1e8) - total liquidity; split equally across all ranges so token need fits AMOUNT0/AMOUNT1.
///   AMOUNT0, AMOUNT1 - in token base units; script transfers these to the router. With split liquidity, 1e6 each is enough for default 1e8.
///   GAS_LIMIT (default 2_000_000) - per-tx gas limit for broadcast.
///
/// Usage: run with --ffi (for htsSetup) and --skip-simulation when using HTS tokens.
///   forge script script/ModifyLiquidityTestnet.s.sol:ModifyLiquidityTestnetScript \
///     --rpc-url https://testnet.hashio.io/api --broadcast --private-key $PRIVATE_KEY --ffi --skip-simulation
contract ModifyLiquidityTestnetScript is Script {
    /// @dev Tick ranges (tickLower, tickUpper) for adding liquidity at different places. Each uses a unique salt.
    function _ranges() internal pure returns (int24[] memory lowers, int24[] memory uppers) {
        lowers = new int24[](3);
        uppers = new int24[](3);
        // Wide range around current price
        (lowers[0], uppers[0]) = (int24(-120), int24(120));
        // Narrower range
        (lowers[1], uppers[1]) = (int24(-60), int24(60));
        // Upper half
        (lowers[2], uppers[2]) = (int24(0), int24(120));
    }

    function run() external {
        htsSetup();

        uint256 PRIVATE_KEY = vm.envUint("PRIVATE_KEY");

        address routerAddr = vm.envAddress("ROUTER_ADDRESS");
        address c0 = vm.envAddress("CURRENCY0_ADDRESS");
        address c1 = vm.envAddress("CURRENCY1_ADDRESS");

        (Currency currency0, Currency currency1) =
            c0 < c1 ? (Currency.wrap(c0), Currency.wrap(c1)) : (Currency.wrap(c1), Currency.wrap(c0));

        uint24 fee = uint24(vm.envOr("FEE", uint256(3000)));
        int24 tickSpacing = int24(uint24(vm.envOr("TICK_SPACING", uint256(60))));
        int128 liquidityDelta = int128(vm.envOr("LIQUIDITY_DELTA", int256(1e8)));

        uint256 amount0 = vm.envOr("AMOUNT0", uint256(0));
        uint256 amount1 = vm.envOr("AMOUNT1", uint256(0));
        uint64 gasLimit = uint64(vm.envOr("GAS_LIMIT", uint256(2_000_000)));

        Router router = Router(payable(routerAddr));

        PoolKey memory key = PoolKey({
            currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: address(0)
        });

        (int24[] memory lowers, int24[] memory uppers) = _ranges();
        uint256 numRanges = lowers.length;
        // Split liquidity across positions so total token need fits AMOUNT0/AMOUNT1 (avoid insufficient balance)
        int128 liquidityPerPosition = int128(int256(liquidityDelta) / int256(uint256(numRanges)));

        vm.startBroadcast(PRIVATE_KEY);

        // 1. Fund router so it can settle for all positions
        if (amount0 > 0 && Currency.unwrap(currency0) != address(0)) {
            require(
                IERC20Minimal(Currency.unwrap(currency0)).transfer{gas: gasLimit}(routerAddr, amount0),
                "ModifyLiquidityTestnet: transfer token0 failed"
            );
            console.log("Transferred token0 to router:", amount0);
        }
        if (amount1 > 0 && Currency.unwrap(currency1) != address(0)) {
            require(
                IERC20Minimal(Currency.unwrap(currency1)).transfer{gas: gasLimit}(routerAddr, amount1),
                "ModifyLiquidityTestnet: transfer token1 failed"
            );
            console.log("Transferred token1 to router:", amount1);
        }

        // 2. Add liquidity at each tick range (different places); liquidity split so tokens suffice
        for (uint256 i = 0; i < numRanges; i++) {
            ModifyLiquidityParams memory params = ModifyLiquidityParams({
                tickLower: lowers[i],
                tickUpper: uppers[i],
                liquidityDelta: int256(liquidityPerPosition),
                salt: bytes32(i) // unique salt per position
            });

            (BalanceDelta callerDelta,) = router.modifyLiquidity{gas: gasLimit}(key, params, "");
            console.log("Position", uint256(i));
            console.log("tickLower", int256(lowers[i]));
            console.log("tickUpper", int256(uppers[i]));
            console.log("amount0", int256(callerDelta.amount0()));
            console.log("amount1", int256(callerDelta.amount1()));
        }

        vm.stopBroadcast();
    }
}
