// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {htsSetup} from "hedera-forking/htsSetup.sol";
import {MockHTS} from "../test/mocks/MockHTS.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {HieroForgeV4Position} from "../src/HieroForgeV4Position.sol";
import {IPoolInitializer_v4} from "../src/interfaces/IPoolInitializer_v4.sol";
import {IMulticall_v4} from "../src/interfaces/IMulticall_v4.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {Currency} from "hieroforge-core/types/Currency.sol";
import {IERC20Minimal} from "hieroforge-core/interfaces/IERC20Minimal.sol";
import {Actions} from "../src/libraries/Actions.sol";

/// @notice Add liquidity via HieroForgeV4Position (same flow as PositionManager): multicall(initializePool, modifyLiquidities(mint position)).
/// Local: set LOCAL_HTS_EMULATION=1 to etch MockHTS at 0x167 (same as tests).
/// Testnet: uses hedera-forking htsSetup() with --ffi so HTS token transfers work.
///
/// Required env: PRIVATE_KEY, HIEROFORGE_V4_POSITION_ADDRESS, CURRENCY0_ADDRESS, CURRENCY1_ADDRESS, AMOUNT0, AMOUNT1
/// Optional: LOCAL_HTS_EMULATION=1, FEE=3000, TICK_SPACING=60, TICK_LOWER=-120, TICK_UPPER=120, LIQUIDITY=1e8, OWNER=(broadcaster),
///   SKIP_BALANCE_CHECK=1 (skip balance require), SKIP_TRANSFER=1 (skip transferring tokens; run TransferToHieroForgeV4Position first)
contract AddLiquidityHieroForgeV4PositionScript is Script {
    address internal constant HTS_PRECOMPILE = address(0x167);
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function run() external {
        if (vm.envOr("LOCAL_HTS_EMULATION", uint256(0)) == 1) {
            MockHTS mockHts = new MockHTS();
            vm.etch(HTS_PRECOMPILE, address(mockHts).code);
            console.log("Local HTS emulation: MockHTS etched at 0x167 (same as tests)");
        } else {
            htsSetup();
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(deployerPrivateKey);
        address hfAddr = vm.envAddress("HIEROFORGE_V4_POSITION_ADDRESS");
        address c0 = vm.envAddress("CURRENCY0_ADDRESS");
        address c1 = vm.envAddress("CURRENCY1_ADDRESS");
        uint256 amount0 = vm.envUint("AMOUNT0");
        uint256 amount1 = vm.envUint("AMOUNT1");

        (address currency0, address currency1) = c0 < c1 ? (c0, c1) : (c1, c0);
        uint24 fee = uint24(vm.envOr("FEE", uint256(3000)));
        int24 tickSpacing = int24(uint24(vm.envOr("TICK_SPACING", uint256(60))));
        int24 tickLower = int24(vm.envOr("TICK_LOWER", int256(-120)));
        int24 tickUpper = int24(vm.envOr("TICK_UPPER", int256(120)));
        uint256 liquidity = vm.envOr("LIQUIDITY", uint256(100_000_000));
        address owner = vm.envOr("OWNER", sender);

        bool skipBalanceCheck = vm.envOr("SKIP_BALANCE_CHECK", uint256(0)) == 1;
        console.log("Sender:", sender);
        if (!skipBalanceCheck) {
            uint256 balance0 = currency0 != address(0) ? IERC20Minimal(currency0).balanceOf(sender) : type(uint256).max;
            uint256 balance1 = currency1 != address(0) ? IERC20Minimal(currency1).balanceOf(sender) : type(uint256).max;
            console.log("Sender balance token0:", balance0, "required:", amount0);
            console.log("Sender balance token1:", balance1, "required:", amount1);
            require(amount0 == 0 || balance0 >= amount0, "AddLiquidityHFV4P: insufficient token0");
            require(amount1 == 0 || balance1 >= amount1, "AddLiquidityHFV4P: insufficient token1");
        } else {
            // On Hedera testnet, balanceOf for HTS tokens may require precompile plumbing and can be flaky in simulation,
            // so we skip both the require and the balanceOf calls when SKIP_BALANCE_CHECK=1.
            console.log("SKIP_BALANCE_CHECK=1: skipping balanceOf + balance require (ensure deployer has tokens on chain)");
            console.log("Required token0:", amount0);
            console.log("Required token1:", amount1);
        }
        if (liquidity >= 1e17 && (amount0 < 1e15 || amount1 < 1e15)) {
            revert("AddLiquidityHFV4P: LIQUIDITY too large for provided AMOUNT0/AMOUNT1");
        }

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: address(0)
        });

        vm.startBroadcast(deployerPrivateKey);

        bool skipTransfer = vm.envOr("SKIP_TRANSFER", uint256(0)) == 1;
        if (!skipTransfer) {
            if (amount0 > 0 && currency0 != address(0)) {
                require(IERC20Minimal(currency0).transfer(hfAddr, amount0), "AddLiquidityHFV4P: transfer token0 failed");
                console.log("Transferred token0 to HFV4P:", amount0);
            }
            if (amount1 > 0 && currency1 != address(0)) {
                require(IERC20Minimal(currency1).transfer(hfAddr, amount1), "AddLiquidityHFV4P: transfer token1 failed");
                console.log("Transferred token1 to HFV4P:", amount1);
            }
        } else {
            console.log("SKIP_TRANSFER=1: assuming tokens already sent to HFV4P");
        }

        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory mintParams = new bytes[](1);
        mintParams[0] =
            abi.encode(poolKey, tickLower, tickUpper, liquidity, uint128(amount0), uint128(amount1), owner, bytes(""));
        bytes memory unlockData = abi.encode(actions, mintParams);
        uint256 deadline = block.timestamp + 3600;

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(IPoolInitializer_v4.initializePool.selector, poolKey, SQRT_PRICE_1_1);
        calls[1] = abi.encodeWithSelector(IPositionManager.modifyLiquidities.selector, unlockData, deadline);
        IMulticall_v4(hfAddr).multicall(calls);

        uint256 tokenId = HieroForgeV4Position(hfAddr).nextTokenId() - 1;
        console.log("Position minted: tokenId", tokenId, "owner", owner);

        vm.stopBroadcast();
    }
}

