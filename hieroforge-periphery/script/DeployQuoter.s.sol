// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {V4Quoter} from "../src/V4Quoter.sol";
import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";

/// @notice Deploys V4Quoter to Hedera testnet (requires PoolManager already deployed).
/// Usage:
///   export PRIVATE_KEY=0x... POOL_MANAGER_ADDRESS=0x...
///   forge script script/DeployQuoter.s.sol:DeployQuoterScript --rpc-url testnet --broadcast --private-key $PRIVATE_KEY
contract DeployQuoterScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address poolManager = vm.envAddress("POOL_MANAGER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        V4Quoter quoter = new V4Quoter(IPoolManager(poolManager));

        vm.stopBroadcast();

        console.log("V4Quoter:", address(quoter));
    }
}
