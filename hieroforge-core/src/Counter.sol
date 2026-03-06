// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @title Counter
/// @notice Minimal contract for testing deployment and verification on Hedera.
contract Counter {
    uint256 public count;

    function increment() external {
        count += 1;
    }

    function set(uint256 _count) external {
        count = _count;
    }
}
