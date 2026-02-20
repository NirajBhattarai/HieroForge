// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {htsSetup} from "hedera-forking/htsSetup.sol";
import {HTS_ADDRESS} from "hedera-forking/HtsSystemContract.sol";
import {IHederaTokenService} from "hedera-forking/IHederaTokenService.sol";
import {HederaResponseCodes} from "hedera-forking/HederaResponseCodes.sol";

/**
 * Tests creating an HTS token via the HTS emulation contract (same flow as CreateTokenScript).
 * Requires --ffi and optionally --fork-url for mirror node.
 */
contract CreateTokenTest is Test {
    address internal signer;

    function setUp() external {
        htsSetup();
        signer = makeAddr("signer");
        vm.deal(signer, 100 ether);
    }

    function test_createFungibleToken() external {
        IHederaTokenService.KeyValue memory keyValue;
        keyValue.inheritAccountKey = true;

        IHederaTokenService.HederaToken memory token;
        token.name = "HTS Token Example Created with Foundry";
        token.symbol = "FDRY";
        token.treasury = signer;
        token.memo = "This HTS Token was created using forge test with HTS emulation";
        token.tokenKeys = new IHederaTokenService.TokenKey[](2);
        token.tokenKeys[0] = IHederaTokenService.TokenKey(0x1, keyValue); // Admin Key
        token.tokenKeys[1] = IHederaTokenService.TokenKey(0x10, keyValue); // Supply Key
        token.expiry = IHederaTokenService.Expiry(0, signer, 8000000);

        vm.prank(signer);
        (int64 responseCode, address tokenAddress) =
            IHederaTokenService(HTS_ADDRESS).createFungibleToken{value: 10 ether}(token, 10000, 4);

        assertEq(responseCode, HederaResponseCodes.SUCCESS, "createFungibleToken should succeed");
        assertNotEq(tokenAddress, address(0), "token address should be set");

        (int64 getCode, IHederaTokenService.TokenInfo memory tokenInfo) =
            IHederaTokenService(HTS_ADDRESS).getTokenInfo(tokenAddress);

        assertEq(getCode, HederaResponseCodes.SUCCESS, "getTokenInfo should succeed");
        assertEq(tokenInfo.token.name, token.name);
        assertEq(tokenInfo.token.symbol, token.symbol);
        assertEq(tokenInfo.token.treasury, signer);
        assertEq(tokenInfo.token.memo, token.memo);
        assertEq(tokenInfo.totalSupply, 10000);
    }
}
