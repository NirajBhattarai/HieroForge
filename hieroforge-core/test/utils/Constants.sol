// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @notice Helpful constants for tests (Uniswap v4-style)
library Constants {
    /// @dev sqrtPriceX96 = floor(sqrt(A / B) * 2**96) where A/B are currency reserves
    uint160 public constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint160 public constant SQRT_PRICE_1_2 = 56022770974786139918731938227;
    uint160 public constant SQRT_PRICE_1_4 = 39614081257132168796771975168;
    uint160 public constant SQRT_PRICE_2_1 = 112045541949572279837463876454;
    uint160 public constant SQRT_PRICE_4_1 = 158456325028528675187087900672;

    uint256 public constant MAX_UINT256 = type(uint256).max;
    uint128 public constant MAX_UINT128 = type(uint128).max;

    address public constant ADDRESS_ZERO = address(0);

    uint24 public constant FEE_LOW = 500;
    uint24 public constant FEE_MEDIUM = 3000;
    uint24 public constant FEE_HIGH = 10000;

    bytes public constant ZERO_BYTES = hex"";
}
