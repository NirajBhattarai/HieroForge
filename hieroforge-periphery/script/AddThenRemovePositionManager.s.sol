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

/// @notice Create/mint a position via PositionManager, then remove by percent and optionally burn.
/// Required env: PRIVATE_KEY, POSITION_MANAGER_ADDRESS, CURRENCY0_ADDRESS, CURRENCY1_ADDRESS, AMOUNT0, AMOUNT1
/// Optional env:
///   FEE=3000, TICK_SPACING=60, TICK_LOWER=-120, TICK_UPPER=120, LIQUIDITY=100000000, OWNER=(sender)
///   REMOVE_PERCENT=25, REMOVE_BURN_AFTER=0 (set 1 to burn after remove)
///   SKIP_TRANSFER=1 (if tokens were transferred to PM already)
contract AddThenRemovePositionManagerScript is Script {
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function run() external {
        Hsc.htsSetup();

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(pk);
        address pmAddr = vm.envAddress("POSITION_MANAGER_ADDRESS");
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
        uint256 removePercent = vm.envOr("REMOVE_PERCENT", uint256(25));
        require(removePercent > 0 && removePercent <= 100, "REMOVE_PERCENT must be 1..100");
        bool removeBurnAfter = vm.envOr("REMOVE_BURN_AFTER", uint256(0)) == 1;

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: address(0)
        });

        vm.startBroadcast(pk);

        bool skipTransfer = vm.envOr("SKIP_TRANSFER", uint256(0)) == 1;
        if (!skipTransfer) {
            if (amount0 > 0 && currency0 != address(0)) {
                require(IERC20Minimal(currency0).transfer(pmAddr, amount0), "AddThenRemove: transfer token0 failed");
            }
            if (amount1 > 0 && currency1 != address(0)) {
                require(IERC20Minimal(currency1).transfer(pmAddr, amount1), "AddThenRemove: transfer token1 failed");
            }
        }

        bytes memory mintActions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory mintParams = new bytes[](1);
        mintParams[0] =
            abi.encode(poolKey, tickLower, tickUpper, liquidity, uint128(amount0), uint128(amount1), owner, bytes(""));
        bytes memory mintUnlockData = abi.encode(mintActions, mintParams);
        uint256 deadline = block.timestamp + 3600;

        bytes[] memory addCalls = new bytes[](2);
        addCalls[0] = abi.encodeWithSelector(IPoolInitializer_v4.initializePool.selector, poolKey, SQRT_PRICE_1_1);
        addCalls[1] = abi.encodeWithSelector(IPositionManager.modifyLiquidities.selector, mintUnlockData, deadline);
        IMulticall_v4(pmAddr).multicall(addCalls);

        uint256 tokenId = PositionManager(pmAddr).nextTokenId() - 1;
        uint128 trackedLiquidity = PositionManager(pmAddr).positionLiquidity(tokenId);
        uint256 removeLiquidity = (uint256(trackedLiquidity) * removePercent) / 100;

        console.log("Minted tokenId:", tokenId, "owner:", owner);
        console.log("Tracked liquidity before remove:", uint256(trackedLiquidity));
        console.log("Remove percent:", removePercent);
        console.log("Remove liquidity:", removeLiquidity);
        console.log("Burn after remove:", removeBurnAfter);

        bytes memory removeActions;
        uint256 stepCount = (removeLiquidity > 0 ? 1 : 0) + (removeBurnAfter ? 1 : 0);
        require(stepCount > 0, "remove step has nothing to do");
        bytes[] memory removeParams = new bytes[](stepCount);
        uint256 i = 0;
        if (removeLiquidity > 0) {
            removeActions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
            removeParams[i++] = abi.encode(tokenId, removeLiquidity, uint128(0), uint128(0), bytes(""));
        }
        if (removeBurnAfter) {
            removeActions = bytes.concat(removeActions, bytes1(uint8(Actions.BURN_POSITION)));
            removeParams[i++] = abi.encode(tokenId, uint128(0), uint128(0), bytes(""));
        }

        IPositionManager(pmAddr).modifyLiquidities(abi.encode(removeActions, removeParams), deadline);

        uint128 afterLiquidity = PositionManager(pmAddr).positionLiquidity(tokenId);
        console.log("Tracked liquidity after remove:", uint256(afterLiquidity));

        vm.stopBroadcast();
    }
}
