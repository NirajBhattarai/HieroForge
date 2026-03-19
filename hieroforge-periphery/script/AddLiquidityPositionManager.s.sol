// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Hsc} from "hedera-forking/Hsc.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {PositionManager} from "../src/PositionManager.sol";
import {IPoolInitializer_v4} from "../src/interfaces/IPoolInitializer_v4.sol";
import {IMulticall_v4} from "../src/interfaces/IMulticall_v4.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {Currency} from "hieroforge-core/types/Currency.sol";
import {IERC20Minimal} from "hieroforge-core/interfaces/IERC20Minimal.sol";
import {Actions} from "../src/libraries/Actions.sol";

/// @notice Add liquidity via PositionManager for currency0 and currency1.
/// Uses multicall to atomically initializePool (if needed) + modifyLiquidities (mint position) in one tx.
/// Uses hedera-forking htsSetup() with --ffi so HTS at 0x167 works (local or testnet fork).
///
/// Required env: PRIVATE_KEY, POSITION_MANAGER_ADDRESS, CURRENCY0_ADDRESS, CURRENCY1_ADDRESS, AMOUNT0, AMOUNT1
/// Optional: FEE=3000, TICK_SPACING=60,
///   TICK_LOWER=-120, TICK_UPPER=120, LIQUIDITY (default 1e8; use 1e18 only if AMOUNT0/AMOUNT1 are ~6e15+), OWNER=(broadcaster),
///   SKIP_BALANCE_CHECK=1 (skip balance require; use when script sees 0 due to fork/simulation but deployer has tokens on chain, e.g. testnet HTS)
///   SKIP_TRANSFER=1 (skip transferring tokens to PM; use when tokens were already sent in a separate tx, e.g. run TransferToPositionManager first on testnet)
///
/// Local: LOCAL_HTS_EMULATION=1 ./scripts/modify.sh
/// Testnet (two-step): 1) ./scripts/transfer-to-position-manager.sh  2) SKIP_TRANSFER=1 ./scripts/modify.sh
contract AddLiquidityPositionManagerScript is Script {
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function run() external {
        Hsc.htsSetup();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(deployerPrivateKey);
        address positionManagerAddr = vm.envAddress("POSITION_MANAGER_ADDRESS");
        address c0 = vm.envAddress("CURRENCY0_ADDRESS");
        address c1 = vm.envAddress("CURRENCY1_ADDRESS");
        uint256 amount0 = vm.envUint("AMOUNT0");
        uint256 amount1 = vm.envUint("AMOUNT1");

        (address currency0, address currency1) = c0 < c1 ? (c0, c1) : (c1, c0);
        uint24 fee = uint24(vm.envOr("FEE", uint256(3000)));
        int24 tickSpacing = int24(uint24(vm.envOr("TICK_SPACING", uint256(60))));
        int24 tickLower = int24(vm.envOr("TICK_LOWER", int256(-120)));
        int24 tickUpper = int24(vm.envOr("TICK_UPPER", int256(120)));
        // Default 1e8 works with AMOUNT0/AMOUNT1=10e6 (e.g. from step-2-hts). 1e18 would need ~6e15 each.
        uint256 liquidity = vm.envOr("LIQUIDITY", uint256(100_000_000));
        address owner = vm.envOr("OWNER", sender);
        console.log("LIQUIDITY (L):", liquidity);

        // Check sender balance before attempting transfers (avoids obscure _transfer: insufficient balance)
        bool skipBalanceCheck = vm.envOr("SKIP_BALANCE_CHECK", uint256(0)) == 1;
        uint256 balance0 = currency0 != address(0) ? IERC20Minimal(currency0).balanceOf(sender) : type(uint256).max;
        uint256 balance1 = currency1 != address(0) ? IERC20Minimal(currency1).balanceOf(sender) : type(uint256).max;
        console.log("Sender (deployer):", sender);
        console.log("Sender balance token0 (currency0):", balance0, "required:", amount0);
        console.log("Sender balance token1 (currency1):", balance1, "required:", amount1);
        if (!skipBalanceCheck) {
            require(
                amount0 == 0 || balance0 >= amount0,
                "AddLiquidity: insufficient token0 (check console for sender balance vs required)"
            );
            require(
                amount1 == 0 || balance1 >= amount1,
                "AddLiquidity: insufficient token1 (check console for sender balance vs required)"
            );
        } else {
            console.log("SKIP_BALANCE_CHECK=1: skipping balance require (ensure deployer has tokens on chain)");
        }
        // With LIQUIDITY=1e18 and range -120..120 at 1:1, pool needs ~6e15 per token. Avoid _transfer: insufficient balance during settle.
        if (liquidity >= 1e17 && (amount0 < 1e15 || amount1 < 1e15)) {
            revert(
                "AddLiquidity: LIQUIDITY is large (1e17+); set AMOUNT0 and AMOUNT1 to at least 6e15 each, or set LIQUIDITY=1e8 for small amounts"
            );
        }

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: address(0)
        });

        vm.startBroadcast(deployerPrivateKey);

        // 1. Transfer currency0 and currency1 to PositionManager (skip if SKIP_TRANSFER=1 and already sent in a prior tx)
        bool skipTransfer = vm.envOr("SKIP_TRANSFER", uint256(0)) == 1;
        if (!skipTransfer) {
            if (amount0 > 0 && currency0 != address(0)) {
                require(
                    IERC20Minimal(currency0).transfer(positionManagerAddr, amount0),
                    "AddLiquidity: transfer token0 failed"
                );
                console.log("Transferred token0 to PositionManager:", amount0);
            }
            if (amount1 > 0 && currency1 != address(0)) {
                require(
                    IERC20Minimal(currency1).transfer(positionManagerAddr, amount1),
                    "AddLiquidity: transfer token1 failed"
                );
                console.log("Transferred token1 to PositionManager:", amount1);
            }
        } else {
            console.log("SKIP_TRANSFER=1: assuming tokens already sent to PositionManager");
        }

        // 2. Encode MINT_POSITION unlock data and deadline
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory mintParams = new bytes[](1);
        mintParams[0] =
            abi.encode(poolKey, tickLower, tickUpper, liquidity, uint128(amount0), uint128(amount1), owner, bytes(""));
        bytes memory unlockData = abi.encode(actions, mintParams);
        uint256 deadline = block.timestamp + 3600;

        // 3. Multicall: initializePool + modifyLiquidities in one tx
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(IPoolInitializer_v4.initializePool.selector, poolKey, SQRT_PRICE_1_1);
        calls[1] = abi.encodeWithSelector(IPositionManager.modifyLiquidities.selector, unlockData, deadline);
        IMulticall_v4(positionManagerAddr).multicall(calls);

        uint256 tokenId = PositionManager(positionManagerAddr).nextTokenId() - 1;
        console.log("Position minted: tokenId", tokenId, "owner", owner);

        vm.stopBroadcast();
    }
}
