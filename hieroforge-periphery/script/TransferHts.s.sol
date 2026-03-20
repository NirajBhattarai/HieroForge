// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Hsc} from "hedera-forking/Hsc.sol";
import {IERC20Minimal} from "hieroforge-core/interfaces/IERC20Minimal.sol";

/// @notice Transfer a single HTS (fungible) token from the deployer to a recipient.
/// Required env: PRIVATE_KEY, HTS_TOKEN_ADDRESS, RECIPIENT_ADDRESS, AMOUNT. Run with --ffi.
contract TransferHtsScript is Script {
    function run() external {
        Hsc.htsSetup();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address token = vm.envAddress("HTS_TOKEN_ADDRESS");
        address recipient = vm.envAddress("RECIPIENT_ADDRESS");
        uint256 amount = vm.envUint("AMOUNT");

        vm.startBroadcast(deployerPrivateKey);

        require(IERC20Minimal(token).transfer(recipient, amount), "TransferHts: transfer failed");
        console.log("Transferred", amount, "to", recipient);

        vm.stopBroadcast();
    }
}
