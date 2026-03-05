// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @notice Minimal ERC20 interface for PoolManager (balanceOf, transfer). Compatible with HTS fungible tokens.
interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
