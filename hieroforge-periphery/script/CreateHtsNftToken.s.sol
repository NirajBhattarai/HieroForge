// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HTS_ADDRESS} from "hedera-forking/HtsSystemContract.sol";
import {IHederaTokenService} from "hedera-forking/IHederaTokenService.sol";
import {Hsc} from "hedera-forking/Hsc.sol";

/// @notice Create an HTS NON_FUNGIBLE_UNIQUE token for PositionManager (position receipt NFTs).
/// The PositionManager contract must be the treasury and have supply key so it can mint.
///
/// Prereq: Deploy PositionManager first with a placeholder HTS_NFT_TOKEN (e.g. 0x0000...01),
/// then run this script with POSITION_MANAGER_ADDRESS set. Then redeploy PositionManager with
/// the new token address.
///
/// Required env: PRIVATE_KEY, POSITION_MANAGER_ADDRESS
/// Optional: HTS_VALUE=(25 ether), HTS_CREATE_GAS_LIMIT=(2000000)
///
/// Run with --ffi and --skip-simulation:
///   forge script script/CreateHtsNftToken.s.sol:CreateHtsNftTokenScript --rpc-url testnet --broadcast --private-key $PRIVATE_KEY --ffi --skip-simulation
/// Or: ./scripts/create-hts-nft-token.sh
contract CreateHtsNftTokenScript is Script {
    function run() external returns (int64 responseCode, address tokenAddress) {
        Hsc.htsSetup();

        uint256 PRIVATE_KEY = vm.envUint("PRIVATE_KEY");
        address positionManager = vm.envAddress("POSITION_MANAGER_ADDRESS");
        uint256 value = vm.envOr("HTS_VALUE", uint256(25 ether));
        uint64 gasLimit = uint64(vm.envOr("HTS_CREATE_GAS_LIMIT", uint256(2_000_000)));

        // Supply key and admin key = PositionManager contract (so it can mint and manage)
        IHederaTokenService.KeyValue memory contractKey;
        contractKey.contractId = positionManager;

        IHederaTokenService.HederaToken memory token;
        token.name = "HieroForge Positions NFT";
        token.symbol = "HF-POS";
        token.treasury = positionManager;
        token.memo = "HTS NFT for HieroForge PositionManager position receipts";
        token.tokenSupplyType = true; // FINITE
        token.maxSupply = 1000000; // max serials
        token.freezeDefault = false;
        token.tokenKeys = new IHederaTokenService.TokenKey[](2);
        token.tokenKeys[0] = IHederaTokenService.TokenKey(0x1, contractKey); // Admin
        token.tokenKeys[1] = IHederaTokenService.TokenKey(0x10, contractKey); // Supply (mint)
        token.expiry = IHederaTokenService.Expiry(0, vm.addr(PRIVATE_KEY), 8000000);

        vm.startBroadcast(PRIVATE_KEY);
        (responseCode, tokenAddress) =
            IHederaTokenService(HTS_ADDRESS).createNonFungibleToken{value: value, gas: gasLimit}(token);
        vm.stopBroadcast();

        console.log("Response code:", uint256(uint64(responseCode)));
        console.log("HTS_NFT_TOKEN (set this in .env and redeploy PositionManager):", tokenAddress);
    }
}
