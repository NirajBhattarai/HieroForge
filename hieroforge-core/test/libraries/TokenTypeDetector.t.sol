// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {TokenTypeDetector} from "../../src/libraries/TokenTypeDetector.sol";
import {Currency} from "../../src/types/Currency.sol";
import {Deployers} from "../utils/Deployers.sol";

/// @notice Minimal ERC20 mock for testing isERC20 / classifyToken (non-HTS)
contract MockERC20 {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }
}

/// @notice Tests for TokenTypeDetector library (isContract, isERC20, isHTS, classifyToken, classifyCurrencies)
contract TokenTypeDetectorTest is Test, Deployers {
    using TokenTypeDetector for address;
    using TokenTypeDetector for Currency;

    MockERC20 public mockErc20;

    function setUp() public {
        initializeManagerRoutersAndPools();
        mockErc20 = new MockERC20();
        mockErc20.mint(address(this), 1000e18);
    }

    // ========== isContract ==========

    function test_isContract_zeroAddress() public view {
        assertFalse(address(0).isContract());
    }

    function test_isContract_eoaHasNoCode() public view {
        assertFalse(address(0x1).isContract());
    }

    function test_isContract_testContractHasCode() public view {
        assertTrue(address(this).isContract());
    }

    function test_isContract_deployedContractHasCode() public view {
        assertTrue(address(mockErc20).isContract());
        assertTrue(Currency.unwrap(currency0).isContract());
    }

    // ========== isERC20 ==========

    function test_isERC20_zeroAddressReturnsFalse() public view {
        assertFalse(address(0).isERC20());
    }

    function test_isERC20_eoaReturnsFalse() public view {
        assertFalse(address(0x1).isERC20());
    }

    function test_isERC20_mockErc20ReturnsTrue() public view {
        assertTrue(address(mockErc20).isERC20());
    }

    function test_isERC20_htsTokensReturnTrue() public view {
        assertTrue(Currency.unwrap(currency0).isERC20());
        assertTrue(Currency.unwrap(currency1).isERC20());
    }

    // ========== isHTS ==========

    function test_isHTS_zeroAddressReturnsFalse() public {
        assertFalse(address(0).isHTS());
    }

    function test_isHTS_eoaReturnsFalse() public {
        assertFalse(address(0x1).isHTS());
    }

    function test_isHTS_mockErc20ReturnsFalse() public {
        assertFalse(address(mockErc20).isHTS());
    }

    function test_isHTS_htsTokensReturnTrue() public {
        assertTrue(Currency.unwrap(currency0).isHTS());
        assertTrue(Currency.unwrap(currency1).isHTS());
    }

    // ========== classifyToken ==========

    function test_classifyToken_zeroIsNone() public {
        assertEq(uint256(address(0).classifyToken()), uint256(TokenTypeDetector.TokenType.None));
    }

    function test_classifyToken_htsIsHTS() public {
        assertEq(uint256(Currency.unwrap(currency0).classifyToken()), uint256(TokenTypeDetector.TokenType.HTS));
        assertEq(uint256(Currency.unwrap(currency1).classifyToken()), uint256(TokenTypeDetector.TokenType.HTS));
    }

    function test_classifyToken_mockErc20IsERC20() public {
        assertEq(uint256(address(mockErc20).classifyToken()), uint256(TokenTypeDetector.TokenType.ERC20));
    }

    function test_classifyToken_eoaIsUnknown() public {
        assertEq(uint256(address(0x1).classifyToken()), uint256(TokenTypeDetector.TokenType.Unknown));
    }

    function test_classifyToken_nonTokenContractIsUnknown() public {
        // Deploy a contract that is not a token (e.g. this test contract)
        assertEq(uint256(address(this).classifyToken()), uint256(TokenTypeDetector.TokenType.Unknown));
    }

    // ========== classifyCurrencies ==========

    function test_classifyCurrencies_htsHts() public {
        (TokenTypeDetector.TokenType type0, TokenTypeDetector.TokenType type1) = currency0.classifyCurrencies(currency1);
        assertEq(uint256(type0), uint256(TokenTypeDetector.TokenType.HTS));
        assertEq(uint256(type1), uint256(TokenTypeDetector.TokenType.HTS));
    }

    function test_classifyCurrencies_erc20Erc20() public {
        Currency c0 = Currency.wrap(address(mockErc20));
        MockERC20 mock2 = new MockERC20();
        mock2.mint(address(this), 1000e18);
        Currency c1 = Currency.wrap(address(mock2));
        (TokenTypeDetector.TokenType type0, TokenTypeDetector.TokenType type1) = c0.classifyCurrencies(c1);
        assertEq(uint256(type0), uint256(TokenTypeDetector.TokenType.ERC20));
        assertEq(uint256(type1), uint256(TokenTypeDetector.TokenType.ERC20));
    }

    function test_classifyCurrencies_erc20Hts() public {
        Currency cErc20 = Currency.wrap(address(mockErc20));
        (TokenTypeDetector.TokenType type0, TokenTypeDetector.TokenType type1) = cErc20.classifyCurrencies(currency0);
        assertEq(uint256(type0), uint256(TokenTypeDetector.TokenType.ERC20));
        assertEq(uint256(type1), uint256(TokenTypeDetector.TokenType.HTS));
    }

    function test_classifyCurrencies_zeroAndHts() public {
        Currency zero = Currency.wrap(address(0));
        (TokenTypeDetector.TokenType type0, TokenTypeDetector.TokenType type1) = zero.classifyCurrencies(currency0);
        assertEq(uint256(type0), uint256(TokenTypeDetector.TokenType.None));
        assertEq(uint256(type1), uint256(TokenTypeDetector.TokenType.HTS));
    }

    // ========== HTS precedence over ERC20 ==========

    function test_classifyToken_htsTakesPrecedenceOverErc20() public {
        // HTS tokens on Hedera also expose ERC-20-like interface; library should classify as HTS first
        TokenTypeDetector.TokenType t = Currency.unwrap(currency0).classifyToken();
        assertEq(uint256(t), uint256(TokenTypeDetector.TokenType.HTS));
    }
}
