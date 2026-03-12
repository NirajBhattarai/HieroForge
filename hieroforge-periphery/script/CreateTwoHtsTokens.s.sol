// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HTS_ADDRESS} from "hedera-forking/HtsSystemContract.sol";
import {IHederaTokenService} from "hedera-forking/IHederaTokenService.sol";
import {htsSetup} from "hedera-forking/htsSetup.sol";

/// @notice Create two HTS fungible tokens for use as pool currencies (step 2 HTS path).
/// Run with --ffi --skip-simulation for testnet:
///   forge script script/CreateTwoHtsTokens.s.sol:CreateTwoHtsTokensScript --rpc-url testnet --broadcast --private-key $PRIVATE_KEY --ffi --skip-simulation
/// Then run scripts/step-2-hts.sh to parse output and update .env with CURRENCY0_ADDRESS, CURRENCY1_ADDRESS, AMOUNT0, AMOUNT1.
contract CreateTwoHtsTokensScript is Script {
    function run() external {
        htsSetup();

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address signer = vm.addr(pk);
        uint256 value = vm.envOr("HTS_VALUE", uint256(25 ether));
        uint64 gasLimit = uint64(vm.envOr("HTS_CREATE_GAS_LIMIT", uint256(2_000_000)));
        uint256 supplyTokens = vm.envOr("INITIAL_SUPPLY", uint256(1_000_000));
        int32 decimals = 4;
        int64 initialSupplyRaw = int64(uint64(supplyTokens * 10 ** uint32(decimals)));

        IHederaTokenService.KeyValue memory keyValue;
        keyValue.inheritAccountKey = true;
        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](2);
        keys[0] = IHederaTokenService.TokenKey(0x1, keyValue); // Admin
        keys[1] = IHederaTokenService.TokenKey(0x10, keyValue); // Supply

        IHederaTokenService.HederaToken memory tokenA;
        tokenA.name = "TokenA";
        tokenA.symbol = "TKA";
        tokenA.treasury = signer;
        tokenA.memo = "";
        tokenA.tokenSupplyType = true;
        tokenA.maxSupply = 2000000000000000000;
        tokenA.freezeDefault = false;
        tokenA.tokenKeys = keys;
        tokenA.expiry = IHederaTokenService.Expiry(0, signer, 8000000);

        IHederaTokenService.HederaToken memory tokenB;
        tokenB.name = "TokenB";
        tokenB.symbol = "TKB";
        tokenB.treasury = signer;
        tokenB.memo = "";
        tokenB.tokenSupplyType = true;
        tokenB.maxSupply = 2000000000000000000;
        tokenB.freezeDefault = false;
        tokenB.tokenKeys = keys;
        tokenB.expiry = IHederaTokenService.Expiry(0, signer, 8000000);

        vm.startBroadcast(pk);

        (int64 codeA, address addrA) = IHederaTokenService(HTS_ADDRESS)
        .createFungibleToken{value: value, gas: gasLimit}(
            tokenA, initialSupplyRaw, decimals
        );
        require(codeA == 22, "CreateTwoHtsTokens: token A failed");
        (int64 codeB, address addrB) = IHederaTokenService(HTS_ADDRESS)
        .createFungibleToken{value: value, gas: gasLimit}(
            tokenB, initialSupplyRaw, decimals
        );
        require(codeB == 22, "CreateTwoHtsTokens: token B failed");

        vm.stopBroadcast();

        (address c0, address c1) = addrA < addrB ? (addrA, addrB) : (addrB, addrA);
        uint256 amountRaw = uint256(uint64(initialSupplyRaw)) / 1000; // e.g. 1000 tokens (4 decimals) for add-liquidity
        if (amountRaw == 0) amountRaw = 10000;

        console.log("TokenA address:", addrA);
        console.log("TokenB address:", addrB);
        console.log("CURRENCY0_ADDRESS (use for pool):", c0);
        console.log("CURRENCY1_ADDRESS (use for pool):", c1);
        console.log("AMOUNT0 (smallest unit):", amountRaw);
        console.log("AMOUNT1 (smallest unit):", amountRaw);
    }
}
