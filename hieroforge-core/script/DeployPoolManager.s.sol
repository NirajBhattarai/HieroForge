// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {Router} from "../test/utils/Router.sol";

/// @notice Deploys PoolManager and Router to the configured network.
/// Usage:
///   forge script script/DeployPoolManager.s.sol:DeployPoolManagerScript --rpc-url $HEDERA_RPC_URL --broadcast --private-key $PRIVATE_KEY
///   # Or use testnet RPC from foundry.toml:
///   forge script script/DeployPoolManager.s.sol:DeployPoolManagerScript --rpc-url testnet --broadcast --private-key $PRIVATE_KEY
contract DeployPoolManagerScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        PoolManager manager = new PoolManager();
        Router router = new Router(IPoolManager(address(manager)));

        vm.stopBroadcast();

        // Log for CI / scripts
        console.log("PoolManager:", address(manager));
        console.log("Router:", address(router));
    }
}
