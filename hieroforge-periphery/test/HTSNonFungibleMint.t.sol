// // SPDX-License-Identifier: Apache-2.0
// pragma solidity ^0.8.24;

// import {Test} from "forge-std/Test.sol";
// import {Hsc} from "hedera-forking/Hsc.sol";
// import {IHederaTokenService} from "hedera-forking/IHederaTokenService.sol";
// import {HederaResponseCodes} from "hedera-forking/HederaResponseCodes.sol";

// contract HTSNonFungibleMintTest is Test {
//     IHederaTokenService public constant HTS = IHederaTokenService(0x167);

//     address public nftToken;           // Will hold the created NFT collection address
//     address public treasury;           // Treasury = this contract for simplicity

//     function setUp() public {
//         // This activates the HTS emulation layer (required for forking)
//         Hsc.htsSetup();

//         treasury = address(this);

//         // === 1. Create a new Non-Fungible Token (NFT Collection) ===
//         IHederaTokenService.Token memory tokenInfo = IHederaTokenService.Token({
//             name: "Test NFT Collection",
//             symbol: "TNFT",
//             treasury: treasury,
//             memo: "Created via Foundry + hedera-forking",
//             tokenSupplyType: false,        // finite = false (unlimited supply)
//             maxSupply: 0,
//             freezeDefault: false,
//             tokenKeys: new IHederaTokenService.TokenKey[](0), // no custom keys for simplicity
//             expiry: IHederaTokenService.Expiry({
//                 second: 0,
//                 autoRenewAccount: address(0),
//                 autoRenewPeriod: 0
//             })
//         });

//         (int64 responseCode, address createdToken) = HTS.createNonFungibleToken(tokenInfo);

//         require(responseCode == HederaResponseCodes.SUCCESS, "Failed to create NFT collection");
//         nftToken = createdToken;

//         console.log(" NFT Collection created at:", nftToken);
//     }

//     function test_MintHTS_NFT() public {
//         // === 2. Mint one NFT ===
//         bytes[] memory metadata = new bytes[](1);
//         metadata[0] = bytes("https://example.com/nft/1.json");   // You can put IPFS, Arweave, or any metadata

//         (int64 rc, int64[] memory serialNumbers) = HTS.mintToken(nftToken, 0, metadata);

//         require(rc == HederaResponseCodes.SUCCESS, "Mint failed");
//         require(serialNumbers.length == 1, "Should mint 1 serial");

//         uint256 serial = uint256(uint64(serialNumbers[0]));

//         console.log("Minted NFT with serial number:", serial);
//         console.log("   Token Address:", nftToken);
//         console.log("   Owner (treasury):", HTS.ownerOf(nftToken, serial));

//         // Optional: Mint multiple NFTs at once
//         // bytes[] memory multiMeta = new bytes[](3);
//         // multiMeta[0] = bytes("ipfs://Qm...1");
//         // multiMeta[1] = bytes("ipfs://Qm...2");
//         // multiMeta[2] = bytes("ipfs://Qm...3");
//         // (rc, serialNumbers) = HTS.mintToken(nftToken, 0, multiMeta);
//     }

//     // Helper to mint multiple NFTs easily
//     function mintMultiple(uint8 count) internal {
//         bytes[] memory metadata = new bytes[](count);
//         for (uint8 i = 0; i < count; i++) {
//             metadata[i] = abi.encodePacked("https://example.com/nft/", i + 1, ".json");
//         }

//         (int64 rc, int64[] memory serials) = HTS.mintToken(nftToken, 0, metadata);
//         require(rc == HederaResponseCodes.SUCCESS, "Multi-mint failed");

//         console.log("Minted", serials.length, "NFTs");
//     }
// }
