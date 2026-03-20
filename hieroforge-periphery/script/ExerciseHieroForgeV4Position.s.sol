// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {HieroForgeV4Position} from "../src/HieroForgeV4Position.sol";
import {Actions} from "../src/libraries/Actions.sol";

/// @notice Exercise HieroForgeV4Position on-chain: increase -> decrease -> burn for an existing tokenId.
/// Required env: PRIVATE_KEY, HIEROFORGE_V4_POSITION_ADDRESS, TOKEN_ID
/// Optional env:
///   INC_LIQUIDITY (default 0), INC_AMOUNT0_MAX (default max), INC_AMOUNT1_MAX (default max)
///   DEC_LIQUIDITY (default 0), DEC_AMOUNT0_MIN (default 0),  DEC_AMOUNT1_MIN (default 0)
///   BURN_AMOUNT0_MIN (default 0), BURN_AMOUNT1_MIN (default 0)
/// If INC_LIQUIDITY/DEC_LIQUIDITY are 0, those steps are skipped.
contract ExerciseHieroForgeV4PositionScript is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address hfAddr = vm.envAddress("HIEROFORGE_V4_POSITION_ADDRESS");
        uint256 tokenId = vm.envUint("TOKEN_ID");

        uint256 incL = vm.envOr("INC_LIQUIDITY", uint256(0));
        uint128 inc0 = uint128(vm.envOr("INC_AMOUNT0_MAX", uint256(type(uint128).max)));
        uint128 inc1 = uint128(vm.envOr("INC_AMOUNT1_MAX", uint256(type(uint128).max)));

        uint256 decL = vm.envOr("DEC_LIQUIDITY", uint256(0));
        uint128 dec0 = uint128(vm.envOr("DEC_AMOUNT0_MIN", uint256(0)));
        uint128 dec1 = uint128(vm.envOr("DEC_AMOUNT1_MIN", uint256(0)));

        uint128 burn0 = uint128(vm.envOr("BURN_AMOUNT0_MIN", uint256(0)));
        uint128 burn1 = uint128(vm.envOr("BURN_AMOUNT1_MIN", uint256(0)));

        vm.startBroadcast(pk);

        uint256 deadline = block.timestamp + 3600;

        if (incL > 0) {
            bytes memory actions = abi.encodePacked(uint8(Actions.INCREASE_LIQUIDITY));
            bytes[] memory params = new bytes[](1);
            params[0] = abi.encode(tokenId, incL, inc0, inc1, bytes(""));
            IPositionManager(hfAddr).modifyLiquidities(abi.encode(actions, params), deadline);
            console.log("Increased liquidity:", incL);
        }

        if (decL > 0) {
            bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
            bytes[] memory params = new bytes[](1);
            params[0] = abi.encode(tokenId, decL, dec0, dec1, bytes(""));
            IPositionManager(hfAddr).modifyLiquidities(abi.encode(actions, params), deadline);
            console.log("Decreased liquidity:", decL);
        }

        {
            bytes memory actions = abi.encodePacked(uint8(Actions.BURN_POSITION));
            bytes[] memory params = new bytes[](1);
            params[0] = abi.encode(tokenId, burn0, burn1, bytes(""));
            IPositionManager(hfAddr).modifyLiquidities(abi.encode(actions, params), deadline);
            console.log("Burned position tokenId:", tokenId);
        }

        // Print tracked liquidity after (should be 0 if burn succeeded)
        console.log("Tracked liquidity after:", HieroForgeV4Position(hfAddr).positionLiquidity(tokenId));

        vm.stopBroadcast();
    }
}

