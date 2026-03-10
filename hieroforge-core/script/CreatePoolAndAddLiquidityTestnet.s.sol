// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {htsSetup} from "hedera-forking/htsSetup.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {Router} from "../test/utils/Router.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {ModifyLiquidityParams} from "../src/types/ModifyLiquidityParams.sol";
import {Currency} from "../src/types/Currency.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {IERC20Minimal} from "../src/interfaces/IERC20Minimal.sol";

/// @notice Create a pool at 1:1 price and add liquidity on testnet.
/// 1. Initializes the pool on PoolManager with sqrtPriceX96 = 1:1.
/// 2. Transfers AMOUNT0/AMOUNT1 to the router (if set).
/// 3. Adds liquidity via Router.
///
/// Required env:
///   PRIVATE_KEY, POOL_MANAGER_ADDRESS, ROUTER_ADDRESS, CURRENCY0_ADDRESS, CURRENCY1_ADDRESS
/// Optional (defaults): FEE=3000, TICK_SPACING=60, TICK_LOWER=-120, TICK_UPPER=120,
///   LIQUIDITY_DELTA=1e8. AMOUNT0/AMOUNT1 fund the router (1e8 works with 1e6 each).
///
/// Usage:
///   export PRIVATE_KEY=0x... POOL_MANAGER_ADDRESS=0x... ROUTER_ADDRESS=0x...
///   export CURRENCY0_ADDRESS=0x... CURRENCY1_ADDRESS=0x...
///   export AMOUNT0=1000000 AMOUNT1=1000000
///   forge script script/CreatePoolAndAddLiquidityTestnet.s.sol:CreatePoolAndAddLiquidityTestnetScript \
///     --rpc-url https://testnet.hashio.io/api --broadcast --private-key $PRIVATE_KEY
contract CreatePoolAndAddLiquidityTestnetScript is Script {
    /// @dev sqrt(1/1) * 2^96 = 1:1 price (same as test/utils/Constants.sol SQRT_PRICE_1_1)
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function run() external {
        htsSetup(); // Required for HTS token transfers (0x167) in simulation
        address managerAddr = vm.envAddress("POOL_MANAGER_ADDRESS");
        address routerAddr = vm.envAddress("ROUTER_ADDRESS");
        address c0 = vm.envAddress("CURRENCY0_ADDRESS");
        address c1 = vm.envAddress("CURRENCY1_ADDRESS");
        uint256 PRIVATE_KEY = vm.envUint("PRIVATE_KEY");

        (Currency currency0, Currency currency1) =
            c0 < c1 ? (Currency.wrap(c0), Currency.wrap(c1)) : (Currency.wrap(c1), Currency.wrap(c0));

        uint24 fee = uint24(vm.envOr("FEE", uint256(3000)));
        int24 tickSpacing = int24(uint24(vm.envOr("TICK_SPACING", uint256(60))));
        int24 tickLower = int24(vm.envOr("TICK_LOWER", int256(-120)));
        int24 tickUpper = int24(vm.envOr("TICK_UPPER", int256(120)));
        // Default 1e8 works with AMOUNT0/AMOUNT1=1e6; use 1e18 only if you fund router with ~6e15 each
        int128 liquidityDelta = int128(vm.envOr("LIQUIDITY_DELTA", int256(1e8)));
        bytes32 salt = vm.envOr("SALT", bytes32(0));

        uint256 amount0 = vm.envOr("AMOUNT0", uint256(0));
        uint256 amount1 = vm.envOr("AMOUNT1", uint256(0));

        IPoolManager manager = IPoolManager(managerAddr);
        Router router = Router(payable(routerAddr));

        PoolKey memory key = PoolKey({
            currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: address(0)
        });

        vm.startBroadcast(PRIVATE_KEY);

        // 1. Create pool at 1:1 price
        int24 tick = manager.initialize(key, SQRT_PRICE_1_1);
        console.log("Pool initialized at 1:1 price, initial tick:", tick);

        // 2. Fund router so it can settle when adding liquidity
        if (amount0 > 0 && Currency.unwrap(currency0) != address(0)) {
            require(
                IERC20Minimal(Currency.unwrap(currency0)).transfer(routerAddr, amount0),
                "CreatePoolAndAddLiquidity: transfer token0 failed"
            );
            console.log("Transferred token0 to router:", amount0);
        }
        if (amount1 > 0 && Currency.unwrap(currency1) != address(0)) {
            require(
                IERC20Minimal(Currency.unwrap(currency1)).transfer(routerAddr, amount1),
                "CreatePoolAndAddLiquidity: transfer token1 failed"
            );
            console.log("Transferred token1 to router:", amount1);
        }

        // // 3. Add liquidity
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: int256(liquidityDelta), salt: salt
        });

        (BalanceDelta callerDelta, BalanceDelta feesAccrued) = router.modifyLiquidity(key, params, "");

        vm.stopBroadcast();

        // console.log("Add liquidity amount0:", callerDelta.amount0());
        // console.log("Add liquidity amount1:", callerDelta.amount1());
        // console.log("Fees accrued amount0:", feesAccrued.amount0());
        // console.log("Fees accrued amount1:", feesAccrued.amount1());
    }
}
