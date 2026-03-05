// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Currency} from "./types/Currency.sol";
import {TokenTypeDetector} from "./libraries/TokenTypeDetector.sol";

/// @title TokenClassifier
/// @notice Exposes ERC-20 vs HTS token detection for pool creation and integration.
/// @dev Pools support any currency combination: ERC20-ERC20, ERC20-HTS, HTS-HTS. Use this contract to identify token types.
contract TokenClassifier {
    /// @notice Classifies a single token address
    function classifyToken(address token) external returns (TokenTypeDetector.TokenType) {
        return TokenTypeDetector.classifyToken(token);
    }

    /// @notice Classifies both currencies of a pool pair
    function classifyCurrencies(Currency currency0, Currency currency1)
        external
        returns (TokenTypeDetector.TokenType type0, TokenTypeDetector.TokenType type1)
    {
        return TokenTypeDetector.classifyCurrencies(currency0, currency1);
    }

    /// @notice Returns true if the address behaves like ERC-20 (view)
    function isERC20(address token) external view returns (bool) {
        return TokenTypeDetector.isERC20(token);
    }

    /// @notice Returns true if the address is a valid HTS token (Hedera; may perform external call)
    function isHTS(address token) external returns (bool) {
        return TokenTypeDetector.isHTS(token);
    }
}
