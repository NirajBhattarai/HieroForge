// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PositionManager} from "../src/PositionManager.sol";
import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";

/// @notice Deploys PositionManager (uses standard ERC721 for position NFTs; no HTS required).
/// Usage:
///   export PRIVATE_KEY=0x... POOL_MANAGER_ADDRESS=0x...
///   forge script script/DeployPositionManager.s.sol:DeployPositionManagerScript --rpc-url testnet --broadcast --private-key $PRIVATE_KEY
contract DeployPositionManagerScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address poolManager = vm.envAddress("POOL_MANAGER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        PositionManager lpm = new PositionManager(IPoolManager(poolManager));

        vm.stopBroadcast();

        console.log("PositionManager:", address(lpm));
    }
}
