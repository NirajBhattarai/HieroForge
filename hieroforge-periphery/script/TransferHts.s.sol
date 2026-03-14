// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {htsSetup} from "hedera-forking/htsSetup.sol";
import {MockHTS} from "../test/mocks/MockHTS.sol";
import {IERC20Minimal} from "hieroforge-core/interfaces/IERC20Minimal.sol";

/// @notice Transfer a single HTS (fungible) token from the deployer to a recipient.
/// Required env: PRIVATE_KEY, HTS_TOKEN_ADDRESS, RECIPIENT_ADDRESS, AMOUNT.
/// Optional: LOCAL_HTS_EMULATION=1 (local node).
contract TransferHtsScript is Script {
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
        address token = vm.envAddress("HTS_TOKEN_ADDRESS");
        address recipient = vm.envAddress("RECIPIENT_ADDRESS");
        uint256 amount = vm.envUint("AMOUNT");

        vm.startBroadcast(deployerPrivateKey);

        require(IERC20Minimal(token).transfer(recipient, amount), "TransferHts: transfer failed");
        console.log("Transferred", amount, "to", recipient);

        vm.stopBroadcast();
    }
}
