// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {htsSetup} from "hedera-forking/htsSetup.sol";
import {MockHTS} from "../test/mocks/MockHTS.sol";
import {IERC20Minimal} from "hieroforge-core/interfaces/IERC20Minimal.sol";

/// @notice Transfer AMOUNT0 and AMOUNT1 to PositionManager in one tx.
/// Use this on testnet first; then run AddLiquidityPositionManager with SKIP_TRANSFER=1 so the add-liquidity script only runs multicall.
/// Required env: PRIVATE_KEY, POSITION_MANAGER_ADDRESS, CURRENCY0_ADDRESS, CURRENCY1_ADDRESS, AMOUNT0, AMOUNT1.
/// Optional: LOCAL_HTS_EMULATION=1 (local node).
contract TransferToPositionManagerScript is Script {
    address internal constant HTS_PRECOMPILE = address(0x167);

    function run() external {
        if (vm.envOr("LOCAL_HTS_EMULATION", uint256(0)) == 1) {
            MockHTS mockHts = new MockHTS();
            vm.etch(HTS_PRECOMPILE, address(mockHts).code);
            console.log("Local HTS emulation: MockHTS etched at 0x167");
        } else {
            htsSetup();
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address positionManagerAddr = vm.envAddress("POSITION_MANAGER_ADDRESS");
        address c0 = vm.envAddress("CURRENCY0_ADDRESS");
        address c1 = vm.envAddress("CURRENCY1_ADDRESS");
        uint256 amount0 = vm.envUint("AMOUNT0");
        uint256 amount1 = vm.envUint("AMOUNT1");

        (address currency0, address currency1) = c0 < c1 ? (c0, c1) : (c1, c0);

        vm.startBroadcast(deployerPrivateKey);

        if (amount0 > 0 && currency0 != address(0)) {
            require(
                IERC20Minimal(currency0).transfer(positionManagerAddr, amount0), "TransferToPM: transfer token0 failed"
            );
            console.log("Transferred token0 to PositionManager:", amount0);
        }
        if (amount1 > 0 && currency1 != address(0)) {
            require(
                IERC20Minimal(currency1).transfer(positionManagerAddr, amount1), "TransferToPM: transfer token1 failed"
            );
            console.log("Transferred token1 to PositionManager:", amount1);
        }

        vm.stopBroadcast();
    }
}
