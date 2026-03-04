// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {ModifyLiquidityRouter} from "../src/ModifyLiquidityRouter.sol";

/// @notice Deploys only the ModifyLiquidityRouter (requires an existing PoolManager).
/// Usage:
///   export POOL_MANAGER_ADDRESS=0x...
///   forge script script/DeployModifyLiquidityRouterOnly.s.sol:DeployModifyLiquidityRouterOnlyScript --rpc-url testnet --broadcast --private-key $PRIVATE_KEY
contract DeployModifyLiquidityRouterOnlyScript is Script {
    function run() external {
        address managerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        ModifyLiquidityRouter router = new ModifyLiquidityRouter(IPoolManager(managerAddress));

        vm.stopBroadcast();

        console.log("ModifyLiquidityRouter:", address(router));
    }
}
