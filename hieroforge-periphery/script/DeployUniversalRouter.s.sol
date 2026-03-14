// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {UniversalRouter} from "../src/UniversalRouter.sol";
import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";

/// @notice Deploys UniversalRouter (requires PoolManager + PositionManager already deployed).
/// Usage:
///   export PRIVATE_KEY=0x... POOL_MANAGER_ADDRESS=0x... POSITION_MANAGER_ADDRESS=0x...
///   forge script script/DeployUniversalRouter.s.sol:DeployUniversalRouterScript --rpc-url testnet --broadcast --private-key $PRIVATE_KEY
contract DeployUniversalRouterScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address poolManager = vm.envAddress("POOL_MANAGER_ADDRESS");
        address positionManager = vm.envAddress("POSITION_MANAGER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        UniversalRouter router = new UniversalRouter(IPoolManager(poolManager), IPositionManager(positionManager));

        vm.stopBroadcast();

        console.log("UniversalRouter:", address(router));
    }
}
