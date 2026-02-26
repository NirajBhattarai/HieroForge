// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PoolManager} from "../src/PoolManager.sol";

/// @notice Deploys PoolManager to the target network (e.g. Hedera testnet).
contract Deploy is Script {
    function run() external returns (PoolManager poolManager) {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        if (deployerPrivateKey != 0) {
            vm.startBroadcast(deployerPrivateKey);
        } else {
            vm.startBroadcast();
        }
        poolManager = new PoolManager();
        vm.stopBroadcast();

        console.log("PoolManager deployed at:", address(poolManager));
    }
}
