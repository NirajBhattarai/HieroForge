// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IERC721Permit_v4
/// @notice Interface for position NFT (Hedera: approve / setApprovalForAll only; no permit)
interface IERC721Permit_v4 {
    error Unauthorized();
}
