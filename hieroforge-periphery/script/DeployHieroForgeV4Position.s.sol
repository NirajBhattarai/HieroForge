// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {HieroForgeV4Position} from "../src/HieroForgeV4Position.sol";
import {htsSetup} from "hedera-forking/htsSetup.sol";

/// @notice Deploy HieroForgeV4Position (HTS NFT collection, no royalties). Same pattern as CreateHtsToken: htsSetup() then broadcast with --ffi --skip-simulation.
/// Env: PRIVATE_KEY or HEDERA_PRIVATE_KEY (ECDSA key for Hedera testnet); OPERATOR_ACCOUNT optional (defaults to signer address).
/// Usage:
///   forge script script/DeployHieroForgeV4Position.s.sol:DeployHieroForgeV4Position --rpc-url testnet --broadcast --private-key $PRIVATE_KEY --ffi --skip-simulation
contract DeployHieroForgeV4Position is Script {
    function run() external {
        htsSetup();

        uint256 PRIVATE_KEY = vm.envOr("HEDERA_PRIVATE_KEY", vm.envUint("PRIVATE_KEY"));
        uint256 value = vm.envOr("HTS_VALUE", uint256(25 ether));
        uint64 gasLimit = uint64(vm.envOr("HTS_CREATE_GAS_LIMIT", uint256(2_000_000)));
        // Operator must be the Hedera ECDSA account that signs the tx (so precompile sees matching key/signature)
        address operatorAccount = vm.envOr("OPERATOR_ACCOUNT", vm.addr(PRIVATE_KEY));

        vm.startBroadcast(PRIVATE_KEY);

        HieroForgeV4Position nft = new HieroForgeV4Position(operatorAccount);
        console.log("HieroForgeV4Position deployed at:", address(nft));

        nft.createCollection{value: value, gas: gasLimit}();
        console.log("HTS NFT collection (no royalties) token address:", nft.tokenAddress());

        vm.stopBroadcast();
    }
}
