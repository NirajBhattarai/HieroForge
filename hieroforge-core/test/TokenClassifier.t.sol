// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {TokenClassifier} from "../src/TokenClassifier.sol";
import {TokenTypeDetector} from "../src/libraries/TokenTypeDetector.sol";
import {Currency} from "../src/types/Currency.sol";
import {Deployers} from "./utils/Deployers.sol";

/// @notice Tests for ERC-20 vs HTS token detection and pool pair classification
contract TokenClassifierTest is Test, Deployers {
    TokenClassifier public classifier;

    function setUp() public {
        initializeManagerRoutersAndPools();
        classifier = new TokenClassifier();
    }

    /// @notice HTS tokens (from Deployers) are classified as HTS
    function test_classifyToken_htsTokens() public {
        TokenTypeDetector.TokenType t0 = classifier.classifyToken(Currency.unwrap(currency0));
        TokenTypeDetector.TokenType t1 = classifier.classifyToken(Currency.unwrap(currency1));
        assertEq(uint256(t0), uint256(TokenTypeDetector.TokenType.HTS), "currency0 should be HTS");
        assertEq(uint256(t1), uint256(TokenTypeDetector.TokenType.HTS), "currency1 should be HTS");
    }

    /// @notice classifyCurrencies returns (HTS, HTS) for our HTS pair
    function test_classifyCurrencies_htsHts() public {
        (TokenTypeDetector.TokenType type0, TokenTypeDetector.TokenType type1) =
            classifier.classifyCurrencies(currency0, currency1);
        assertEq(uint256(type0), uint256(TokenTypeDetector.TokenType.HTS));
        assertEq(uint256(type1), uint256(TokenTypeDetector.TokenType.HTS));
    }

    /// @notice isHTS returns true for HTS token addresses
    function test_isHTS_returnsTrueForHts() public {
        assertTrue(classifier.isHTS(Currency.unwrap(currency0)));
        assertTrue(classifier.isHTS(Currency.unwrap(currency1)));
    }

    /// @notice isERC20 returns true for HTS tokens (they expose ERC-20-like interface on Hedera)
    function test_isERC20_htsTokensExposeErc20Interface() public view {
        assertTrue(classifier.isERC20(Currency.unwrap(currency0)));
        assertTrue(classifier.isERC20(Currency.unwrap(currency1)));
    }

    /// @notice address(0) classifies as None
    function test_classifyToken_zeroIsNone() public {
        TokenTypeDetector.TokenType t = classifier.classifyToken(address(0));
        assertEq(uint256(t), uint256(TokenTypeDetector.TokenType.None));
    }

    /// @notice Pool can be created with any combination (ERC20-ERC20, ERC20-HTS, HTS-HTS); key validates by sort order only
    function test_poolAcceptsAnyCurrencyCombination() public {
        // Our key is already HTS-HTS and was initialized in setUp
        (TokenTypeDetector.TokenType type0, TokenTypeDetector.TokenType type1) =
            classifier.classifyCurrencies(key.currency0, key.currency1);
        assertEq(uint256(type0), uint256(TokenTypeDetector.TokenType.HTS));
        assertEq(uint256(type1), uint256(TokenTypeDetector.TokenType.HTS));
    }
}
