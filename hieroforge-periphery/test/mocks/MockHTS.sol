// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @notice Mock Hedera Token Service precompile for tests. Etch at 0x167 so mintToken/transferFromNFT succeed.
contract MockHTS {
    int64 public constant SUCCESS = 22;

    bytes4 private constant MINT_TOKEN_SELECTOR = 0xe0f4059a; // mintToken(address,int64,bytes[])
    bytes4 private constant TRANSFER_NFT_SELECTOR = 0x9b23d3d9; // transferFromNFT(address,address,address,uint256)

    fallback(bytes calldata) external returns (bytes memory) {
        bytes4 sel = bytes4(msg.data[:4]);
        if (sel == MINT_TOKEN_SELECTOR) {
            int64[] memory serials = new int64[](1);
            serials[0] = 1;
            return abi.encode(SUCCESS, int64(1), serials);
        }
        if (sel == TRANSFER_NFT_SELECTOR) {
            return abi.encode(SUCCESS);
        }
        revert("MockHTS: unknown selector");
    }
}
