// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @title ERC721Positions
/// @notice Simple ERC721 for position receipt NFTs. No HTS dependency — easy to test; switch to HTS/ERC721 later if needed.
abstract contract ERC721Positions {
    string private _name;
    string private _symbol;

    mapping(uint256 tokenId => address) private _owners;
    mapping(address owner => uint256) private _balanceOf;
    mapping(uint256 tokenId => address) private _tokenApprovals;
    mapping(address owner => mapping(address operator => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    error NotApproved(address caller);
    error TokenDoesNotExist();
    error InvalidOwner();
    error MintToZero();
    error TokenAlreadyMinted();

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function ownerOf(uint256 tokenId) public view virtual returns (address) {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert TokenDoesNotExist();
        return owner;
    }

    function balanceOf(address owner) external view virtual returns (uint256) {
        if (owner == address(0)) revert InvalidOwner();
        return _balanceOf[owner];
    }

    function getApproved(uint256 tokenId) public view virtual returns (address) {
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(address owner, address operator) public view virtual returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function approve(address approved, uint256 tokenId) external virtual {
        address owner = ownerOf(tokenId);
        if (msg.sender != owner && !isApprovedForAll(owner, msg.sender)) revert NotApproved(msg.sender);
        _tokenApprovals[tokenId] = approved;
        emit Approval(owner, approved, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external virtual {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function _isApprovedOrOwner(address caller, uint256 tokenId) internal view virtual returns (bool) {
        address owner = ownerOf(tokenId);
        return caller == owner || getApproved(tokenId) == caller || isApprovedForAll(owner, caller);
    }

    modifier onlyIfApproved(address caller, uint256 tokenId) {
        if (!_isApprovedOrOwner(caller, tokenId)) revert NotApproved(caller);
        _;
    }

    /// @dev Mints position NFT to `to` with `tokenId`. Standard ERC721 mint (no HTS).
    function _mint(address to, uint256 tokenId) internal virtual {
        if (to == address(0)) revert MintToZero();
        if (_owners[tokenId] != address(0)) revert TokenAlreadyMinted();
        _owners[tokenId] = to;
        unchecked {
            _balanceOf[to]++;
        }
        emit Transfer(address(0), to, tokenId);
    }
}
