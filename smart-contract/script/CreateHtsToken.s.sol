// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {
    TokenCreateContract
} from "hedera-smart-contracts/system-contracts/hedera-token-service/examples/token-create/TokenCreateContract.sol";

/// @notice Deploys the HTS token-create contract and creates a fungible token on Hedera.
/// Run on Hedera testnet or local node (HTS precompile at 0x167).
/// Usage:
///   forge script script/CreateHtsToken.s.sol:CreateHtsTokenScript --rpc-url $HEDERA_RPC_URL --broadcast --private-key $PRIVATE_KEY
/// For local node: HEDERA_RPC_URL often https://localhost:7546 (or your Hedera EVM RPC).
contract CreateHtsTokenScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envOr("TREASURY", vm.addr(deployerPrivateKey));

        vm.startBroadcast(deployerPrivateKey);

        TokenCreateContract tokenCreate = new TokenCreateContract();
        // Creates token with name "tokenName", symbol "tokenSymbol", 10B initial supply, 0 decimals.
        // Treasury receives the initial supply. Requires some HBAR for fees.
        tokenCreate.createFungibleTokenPublic{value: 0}(treasury);

        vm.stopBroadcast();
    }
}
