// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {IERC20Minimal} from "../interfaces/IERC20Minimal.sol";
import {Currency} from "../types/Currency.sol";

/// @notice Minimal view interface used only for ERC-20 detection (totalSupply + balanceOf)
interface IERC20Detection {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Minimal HTS precompile interface for token detection (Hedera)
interface IHTSMinimal {
    function isToken(address token) external returns (int64 responseCode, bool isToken);
}

/// @title TokenTypeDetector
/// @notice Identifies whether a contract address is an ERC-20 token or an HTS (Hedera Token Service) token.
/// @dev Pools support any combination: ERC20-ERC20, ERC20-HTS, HTS-HTS. Use this library to classify currencies.
library TokenTypeDetector {
    /// @dev HTS system precompile address (same on Hedera testnet and mainnet)
    address internal constant HTS_PRECOMPILE = address(0x167);

    /// @dev Hedera response code for success (from HederaResponseCodes.SUCCESS)
    int64 internal constant HTS_SUCCESS = 22;

    enum TokenType {
        None,
        ERC20,
        HTS,
        Unknown
    }

    /// @notice Returns true if the address has contract code (not EOA)
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly ("memory-safe") {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /// @notice Returns true if the address behaves like a standard ERC-20 (totalSupply + balanceOf succeed)
    function isERC20(address token) internal view returns (bool) {
        if (token == address(0) || !isContract(token)) return false;
        try IERC20Detection(token).totalSupply() returns (uint256) {
            try IERC20Detection(token).balanceOf(address(this)) returns (uint256) {
                return true;
            } catch {}
        } catch {}
        return false;
    }

    /// @notice Returns true if the address is a valid HTS token (Hedera precompile isToken returns success)
    /// @dev On non-Hedera chains, 0x167 may revert or return non-success; this returns false in that case.
    function isHTS(address token) internal returns (bool) {
        if (token == address(0) || !isContract(token)) return false;
        try IHTSMinimal(HTS_PRECOMPILE).isToken(token) returns (int64 responseCode, bool isToken_) {
            return responseCode == HTS_SUCCESS && isToken_;
        } catch {
            return false;
        }
    }

    /// @notice Classifies a token: HTS takes precedence over ERC20 (e.g. HTS tokens on Hedera may also expose ERC-20-like interface)
    function classifyToken(address token) internal returns (TokenType) {
        if (token == address(0)) return TokenType.None;
        if (isHTS(token)) return TokenType.HTS;
        if (isERC20(token)) return TokenType.ERC20;
        return TokenType.Unknown;
    }

    /// @notice Classifies both currencies of a pool pair (ERC20-ERC20, ERC20-HTS, HTS-HTS, etc.)
    function classifyCurrencies(Currency currency0, Currency currency1)
        internal
        returns (TokenType type0, TokenType type1)
    {
        type0 = classifyToken(Currency.unwrap(currency0));
        type1 = classifyToken(Currency.unwrap(currency1));
    }
}
