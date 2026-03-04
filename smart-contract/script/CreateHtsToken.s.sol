// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HTS_ADDRESS} from "hedera-forking/HtsSystemContract.sol";
import {IHederaTokenService} from "hedera-forking/IHederaTokenService.sol";
import {htsSetup} from "hedera-forking/htsSetup.sol";

/**
 * Create an HTS fungible token on Hedera testnet.
 * Uses hedera-forking htsSetup() so local simulation succeeds (Hedera RPC returns 0xfe for 0x167 otherwise).
 * Run with --ffi and --skip-simulation, e.g.:
 *   forge script script/CreateHtsToken.s.sol:CreateHtsTokenScript --rpc-url testnet --broadcast --private-key $PRIVATE_KEY --ffi --skip-simulation
 * Or: ./scripts/deploy-token.sh
 *
 * NOTE: With --skip-simulation, the script runs locally against the HTS *emulation* to build the tx.
 * The printed "Token address" is from that emulation and is always 0x...0408 (first token id 1032).
 * The REAL token address on Hedera is assigned by the network—get it from the broadcast tx on HashScan
 * (transaction receipt / contract call result to 0x167).
 */
contract CreateHtsTokenScript is Script {
    function run() external returns (address signer, int64 responseCode, address tokenAddress) {
        htsSetup();

        uint256 PRIVATE_KEY = vm.envUint("PRIVATE_KEY");
        signer = vm.addr(PRIVATE_KEY);
        uint256 value = vm.envOr("HTS_VALUE", uint256(25 ether)); // TokenCreate ~$1; 25 HBAR buffer for fees
        uint64 gasLimit = uint64(vm.envOr("HTS_CREATE_GAS_LIMIT", uint256(2_000_000))); // relay can't estimate HTS; too low → INSUFFICIENT_TX_FEE

        IHederaTokenService.KeyValue memory keyValue;
        keyValue.inheritAccountKey = true;

        IHederaTokenService.HederaToken memory token;
        token.name = "Token2";
        token.symbol = "Token2";
        token.treasury = signer;
        token.memo = "This HTS Token was created using forge script together with HTS emulation";
        token.tokenSupplyType = true;
        token.maxSupply = 20_000_000_000;
        token.freezeDefault = false;
        token.tokenKeys = new IHederaTokenService.TokenKey[](2);
        token.tokenKeys[0] = IHederaTokenService.TokenKey(0x1, keyValue); // Admin Key
        token.tokenKeys[1] = IHederaTokenService.TokenKey(0x10, keyValue); // Supply Key (enables minting)
        token.expiry = IHederaTokenService.Expiry(0, signer, 8000000);

        vm.startBroadcast(PRIVATE_KEY);
        (responseCode, tokenAddress) = IHederaTokenService(HTS_ADDRESS)
        .createFungibleToken{value: value, gas: gasLimit}(
            token, 1_000_000 * 10 ** 4, 4
        ); // 1M tokens (4 decimals)
        vm.stopBroadcast();

        console.log("Signer (treasury):", signer);
        console.log("Response code:", uint256(uint64(responseCode)));
        console.log("Token address (from local HTS emulation; real address is on HashScan):", tokenAddress);
    }
}
