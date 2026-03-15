// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {htsSetup} from "hedera-forking/htsSetup.sol";

import {PoolManager} from "../src/PoolManager.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {Router} from "../test/utils/Router.sol";
import {HookDeployer} from "../src/deployers/HookDeployer.sol";
import {TWAPOracleHook} from "../src/hooks/TWAPOracleHook.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";
import {Hooks} from "../src/libraries/Hooks.sol";

import {PoolKey} from "../src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "../src/types/PoolId.sol";
import {Currency} from "../src/types/Currency.sol";
import {SwapParams} from "../src/types/SwapParams.sol";
import {ModifyLiquidityParams} from "../src/types/ModifyLiquidityParams.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {IERC20Minimal} from "../src/interfaces/IERC20Minimal.sol";

/// @notice Deploy the full hook infrastructure to Hedera testnet:
///   1. PoolManager (with hook support)
///   2. HookDeployer (CREATE2 factory)
///   3. TWAPOracleHook (deployed via CREATE2 at address with correct permission bits)
///   4. Router (for swap + liquidity operations)
///   5. Initialize a pool with the TWAP hook
///   6. Add liquidity
///   7. Execute a test swap
///   8. Query the TWAP oracle
///
/// Required env:
///   PRIVATE_KEY         – 0x-prefixed ECDSA private key (funded with HBAR)
///   CURRENCY0_ADDRESS   – Lower-addressed token (EVM address)
///   CURRENCY1_ADDRESS   – Higher-addressed token (EVM address)
///
/// Optional env:
///   FEE=3000  TICK_SPACING=60  AMOUNT0=1000000  AMOUNT1=1000000
///
/// Usage:
///   forge script script/DeployHooksTestnet.s.sol:DeployHooksTestnetScript \
///     --rpc-url testnet --broadcast --private-key $PRIVATE_KEY
contract DeployHooksTestnetScript is Script {
    using PoolIdLibrary for PoolKey;

    /// @dev sqrt(1/1) * 2^96 = 1:1 price
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    /// TWAPOracleHook flags: AFTER_INITIALIZE (bit 1) | AFTER_SWAP (bit 5) = 0x22
    uint160 internal constant TWAP_FLAGS = Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG;

    function run() external {
        htsSetup();

        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address c0 = vm.envAddress("CURRENCY0_ADDRESS");
        address c1 = vm.envAddress("CURRENCY1_ADDRESS");

        // Ensure currency0 < currency1 for canonical ordering
        (Currency currency0, Currency currency1) =
            c0 < c1 ? (Currency.wrap(c0), Currency.wrap(c1)) : (Currency.wrap(c1), Currency.wrap(c0));

        uint24 fee = uint24(vm.envOr("FEE", uint256(3000)));
        int24 tickSpacing = int24(uint24(vm.envOr("TICK_SPACING", uint256(60))));
        uint256 amount0 = vm.envOr("AMOUNT0", uint256(1000000));
        uint256 amount1 = vm.envOr("AMOUNT1", uint256(1000000));

        // ──── Phase 1: Deploy core contracts ────────────────────────────────

        vm.startBroadcast(deployerPk);

        // 1. PoolManager
        PoolManager poolManager = new PoolManager();
        console.log("PoolManager:", address(poolManager));

        // 2. HookDeployer (CREATE2 factory)
        HookDeployer hookDeployer = new HookDeployer();
        console.log("HookDeployer:", address(hookDeployer));

        // 3. Mine salt for TWAPOracleHook address with correct permission bits
        (address expectedHookAddr, bytes32 salt) = HookMiner.find(
            address(hookDeployer), TWAP_FLAGS, type(TWAPOracleHook).creationCode, abi.encode(address(poolManager))
        );
        console.log("Expected TWAP hook address:", expectedHookAddr);
        console.log("Salt (uint256):", uint256(salt));

        // 4. Deploy TWAPOracleHook via CREATE2
        bytes memory twapCreationCode =
            abi.encodePacked(type(TWAPOracleHook).creationCode, abi.encode(address(poolManager)));
        address twapHook = hookDeployer.deploy(salt, twapCreationCode);
        console.log("TWAPOracleHook deployed at:", twapHook);

        // Verify the address matches and has correct permission bits
        require(twapHook == expectedHookAddr, "Hook address mismatch!");
        require(uint160(twapHook) & 0x3F == uint160(TWAP_FLAGS), "Hook permission bits incorrect!");
        console.log("Hook permission bits verified: 0x22 (AFTER_INITIALIZE | AFTER_SWAP)");

        // 5. Router
        Router router = new Router(IPoolManager(address(poolManager)));
        console.log("Router:", address(router));

        // ──── Phase 2: Create pool with TWAP hook ───────────────────────────

        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: twapHook});

        int24 tick = poolManager.initialize(key, SQRT_PRICE_1_1);
        console.log("Pool initialized with TWAP hook, tick:", tick);

        // ──── Phase 3: Add liquidity ────────────────────────────────────────

        // Fund router with tokens
        if (amount0 > 0 && Currency.unwrap(currency0) != address(0)) {
            IERC20Minimal(Currency.unwrap(currency0)).transfer(address(router), amount0);
            console.log("Transferred token0 to router:", amount0);
        }
        if (amount1 > 0 && Currency.unwrap(currency1) != address(0)) {
            IERC20Minimal(Currency.unwrap(currency1)).transfer(address(router), amount1);
            console.log("Transferred token1 to router:", amount1);
        }

        ModifyLiquidityParams memory addParams = ModifyLiquidityParams({
            tickLower: int24(-120), tickUpper: int24(120), liquidityDelta: int256(1e8), salt: bytes32(0)
        });

        (BalanceDelta lpDelta,) = router.modifyLiquidity(key, addParams, "");
        console.log("Liquidity added successfully");

        // ──── Phase 4: Execute test swap ────────────────────────────────────

        // Fund router for the swap
        if (Currency.unwrap(currency0) != address(0)) {
            IERC20Minimal(Currency.unwrap(currency0)).transfer(address(router), 10000);
        }

        SwapParams memory swapParams = SwapParams({
            amountSpecified: -int256(1000), // exact input 1000 of token0
            tickSpacing: tickSpacing,
            zeroForOne: true,
            sqrtPriceLimitX96: uint160(4295128739 + 1), // MIN_SQRT_PRICE + 1
            lpFeeOverride: 0
        });

        BalanceDelta swapDelta = router.swap(key, swapParams, "");
        console.log("Swap executed through TWAP hook");

        // ──── Phase 5: Query TWAP oracle ────────────────────────────────────

        PoolId id = key.toId();

        // Check observation count
        uint256 obsCount = TWAPOracleHook(twapHook).getObservationCount(id);
        console.log("TWAP observation count:", obsCount);

        // Query last tick (secondsAgo = 0)
        int24 lastTick = TWAPOracleHook(twapHook).observe(id, 0);
        console.log("TWAP last tick:", lastTick);

        // Check pool is initialized in hook
        bool initialized = TWAPOracleHook(twapHook).poolInitialized(id);
        console.log("Pool initialized in hook:", initialized);

        vm.stopBroadcast();

        // ──── Summary ───────────────────────────────────────────────────────

        console.log("");
        console.log("=== DEPLOYMENT SUMMARY ===");
        console.log("PoolManager:     ", address(poolManager));
        console.log("HookDeployer:    ", address(hookDeployer));
        console.log("TWAPOracleHook:  ", twapHook);
        console.log("Router:          ", address(router));
        console.log("Currency0:       ", Currency.unwrap(currency0));
        console.log("Currency1:       ", Currency.unwrap(currency1));
        console.log("Pool fee:        ", fee);
        console.log("Tick spacing:    ", tickSpacing);
        console.log("Hook flags:      ", "AFTER_INITIALIZE | AFTER_SWAP");
        console.log("TWAP observations:", obsCount);
        console.log("========================");
    }
}
