// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PoolManager} from "../src/PoolManager.sol";

/// @notice Deploys only the PoolManager contract (no router).
/// Use this when you only need the core pool manager; deploy ModifyLiquidityRouter separately if needed.
/// Usage:
///   forge script script/DeployPoolManagerOnly.s.sol:DeployPoolManagerOnlyScript --rpc-url testnet --broadcast --private-key $PRIVATE_KEY
contract DeployPoolManagerOnlyScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        PoolManager manager = new PoolManager();

        vm.stopBroadcast();

        console.log("PoolManager:", address(manager));
    }
}
