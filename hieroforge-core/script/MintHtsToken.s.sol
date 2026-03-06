// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HTS_ADDRESS} from "hedera-forking/HtsSystemContract.sol";
import {IHederaTokenService} from "hedera-forking/IHederaTokenService.sol";
import {htsSetup} from "hedera-forking/htsSetup.sol";

/**
 * Mint additional supply of an HTS fungible token and optionally send to an address.
 * The token must have been created with a Supply Key; the signer (PRIVATE_KEY) must be
 * the token treasury (or have supply key) to mint.
 *
 * Env:
 *   PRIVATE_KEY     - signer (must be treasury or have supply key)
 *   TOKEN_ADDRESS   - HTS token EVM address
 *   MINT_AMOUNT     - amount to mint, in token units (e.g. 1000 = 1000 tokens)
 *   MINT_TO_ADDRESS - (optional) address to receive the minted tokens; if not set, tokens stay in treasury
 *   TOKEN_DECIMALS  - (optional) token decimals, default 4
 *
 * Run: forge script script/MintHtsToken.s.sol:MintHtsTokenScript --rpc-url testnet --broadcast --private-key $PRIVATE_KEY --ffi --skip-simulation
 * Or: ./scripts/mint-token.sh
 */
contract MintHtsTokenScript is Script {
    function run() external {
        htsSetup();

        uint256 PRIVATE_KEY = vm.envUint("PRIVATE_KEY");
        address signer = vm.addr(PRIVATE_KEY);
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        uint256 mintAmountTokens = vm.envOr("MINT_AMOUNT", uint256(1000));
        uint32 decimals = uint32(vm.envOr("TOKEN_DECIMALS", uint256(4)));
        int64 amountRaw = int64(uint64(mintAmountTokens * 10 ** decimals));

        vm.startBroadcast(PRIVATE_KEY);

        // Mint to treasury (signer must be treasury or have supply key)
        bytes[] memory metadata;
        (int64 responseCode, int64 newTotalSupply,) =
            IHederaTokenService(HTS_ADDRESS).mintToken(tokenAddress, amountRaw, metadata);
        require(responseCode == 22, "MintHtsToken: mint failed"); // 22 = SUCCESS

        console.log(
            "Minted (to treasury):",
            uint256(uint64(amountRaw)),
            "raw; new total supply:",
            uint256(uint64(newTotalSupply))
        );

        // Optionally transfer to another address
        address mintTo = vm.envOr("MINT_TO_ADDRESS", address(0));
        if (mintTo != address(0) && mintTo != signer) {
            int64 transferCode = IHederaTokenService(HTS_ADDRESS).transferToken(tokenAddress, signer, mintTo, amountRaw);
            require(transferCode == 22, "MintHtsToken: transfer to recipient failed");
            console.log("Transferred to:", mintTo);
        }

        vm.stopBroadcast();
    }
}
