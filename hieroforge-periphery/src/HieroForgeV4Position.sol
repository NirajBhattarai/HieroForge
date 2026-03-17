// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {HTS_ADDRESS} from "hedera-forking/HtsSystemContract.sol";
import {IHederaTokenService} from "hedera-forking/IHederaTokenService.sol";
import {HederaResponseCodes} from "hedera-forking/HederaResponseCodes.sol";
import {IERC721} from "hedera-forking/IERC721.sol";

/// @title HieroForgeV4Position
/// @notice HTS NFT collection for HieroForge V4 positions. NO ROYALTIES (0% on secondary). Create + mint only.
contract HieroForgeV4Position {
    address public tokenAddress;
    string public name = "HieroForge V4 Position";
    string public symbol = "HFV4P";

    bytes private constant DEFAULT_METADATA = hex"01";

    address public owner;
    /// @notice Hedera ECDSA account used for token expiry autoRenew. Must match PRIVATE_KEY signer so precompile signature is valid.
    address public operatorAccount;

    event NFTCollectionCreated(address indexed token);
    event NFTMinted(address indexed to, uint256 indexed tokenId);

    error OnlyOwner();
    error HtsCreationFailed();
    error HtsMintFailed();
    error CollectionAlreadyCreated();

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address _operatorAccount) {
        owner = msg.sender;
        operatorAccount = _operatorAccount;
    }

    /// @notice One-time HTS NFT collection creation. Call from deploy script with {value: HTS_VALUE, gas: HTS_CREATE_GAS_LIMIT} so relay gets gas_limit.
    /// expiry.autoRenewAccount must be the Hedera ECDSA account that signs the tx (operatorAccount) to avoid INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE.
    function createCollection() external payable onlyOwner {
        if (tokenAddress != address(0)) revert CollectionAlreadyCreated();

        IHederaTokenService.KeyValue memory contractKey;
        contractKey.contractId = address(this);

        IHederaTokenService.HederaToken memory token;
        token.name = name;
        token.symbol = symbol;
        token.treasury = address(this);
        token.memo = "";
        token.tokenSupplyType = true;
        token.maxSupply = 1_000_000;
        token.freezeDefault = false;
        token.tokenKeys = new IHederaTokenService.TokenKey[](2);
        token.tokenKeys[0] = IHederaTokenService.TokenKey(0x1, contractKey);   // ADMIN
        token.tokenKeys[1] = IHederaTokenService.TokenKey(0x10, contractKey);  // SUPPLY
        // MUST be the Hedera ECDSA account backing PRIVATE_KEY (same as tx signer) for precompile signature validation
        token.expiry = IHederaTokenService.Expiry(0, address(0), 8_000_000);

        (int64 rc, address created) = IHederaTokenService(HTS_ADDRESS).createNonFungibleToken{value: msg.value}(token);
        if (rc != HederaResponseCodes.SUCCESS) revert HtsCreationFailed();

        tokenAddress = created;
        emit NFTCollectionCreated(created);
    }

    function mintNFT(address to) external onlyOwner returns (uint256) {
        bytes[] memory metadata = new bytes[](1);
        metadata[0] = DEFAULT_METADATA;

        (int64 rc, , int64[] memory serials) =
            IHederaTokenService(HTS_ADDRESS).mintToken(tokenAddress, 0, metadata);
        if (rc != HederaResponseCodes.SUCCESS) revert HtsMintFailed();

        uint256 tokenId = uint256(uint64(serials[0]));
        IERC721(tokenAddress).transferFrom(address(this), to, tokenId);

        emit NFTMinted(to, tokenId);
        return tokenId;
    }
}
