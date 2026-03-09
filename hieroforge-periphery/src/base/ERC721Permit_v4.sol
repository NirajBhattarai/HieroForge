// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {IERC721Permit_v4} from "../interfaces/IERC721Permit_v4.sol";

/// @title ERC721 for position NFTs (Hedera: use approve / setApprovalForAll only)
abstract contract ERC721Permit_v4 is ERC721, IERC721Permit_v4 {
    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

    /// @notice Reverts if the caller is not the owner or approved for the token (for use by PositionManager)
    modifier onlyIfApproved(address caller, uint256 tokenId) {
        if (!_isApprovedOrOwner(caller, tokenId)) revert Unauthorized();
        _;
    }

    /// @dev Override Solmate's setApprovalForAll
    function setApprovalForAll(address operator, bool approved) public override {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /// @dev Override Solmate's approve
    function approve(address spender, uint256 id) public override {
        address owner = _ownerOf[id];
        if (msg.sender != owner && !isApprovedForAll[owner][msg.sender]) revert Unauthorized();
        getApproved[id] = spender;
        emit Approval(owner, spender, id);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        return spender == ownerOf(tokenId) || getApproved[tokenId] == spender
            || isApprovedForAll[ownerOf(tokenId)][spender];
    }

    /// @dev Solmate ERC721 requires tokenURI; return empty string for position NFTs
    function tokenURI(uint256) public view virtual override returns (string memory) {
        return "";
    }
}
