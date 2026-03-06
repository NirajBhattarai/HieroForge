// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

/// @title QuoterRevert
/// @notice Revert with quote amount and parse it from catch data (no view swap in core)
library QuoterRevert {
    /// @notice Thrown when invalid revert bytes are returned by the quote simulation
    error UnexpectedRevertBytes(bytes revertData);

    /// @notice Thrown with the quote amount; caught and parsed by the quoter
    error QuoteSwap(uint256 amount);

    /// @notice Reverts with QuoteSwap(quoteAmount) so the caller can catch and parse
    function revertQuote(uint256 quoteAmount) internal pure {
        revert QuoteSwap(quoteAmount);
    }

    /// @notice Reverts using revertData (bubbles up QuoteSwap or other simulation error)
    function bubbleReason(bytes memory revertData) internal pure {
        assembly ("memory-safe") {
            revert(add(revertData, 0x20), mload(revertData))
        }
    }

    /// @notice Returns the amount from a QuoteSwap revert; reverts with UnexpectedRevertBytes if not QuoteSwap
    function parseQuoteAmount(bytes memory reason) internal pure returns (uint256 quoteAmount) {
        // QuoteSwap(uint256) = 4-byte selector + 32-byte amount. Amount at offset 4 in the payload.
        if (reason.length != 36) revert UnexpectedRevertBytes(reason);
        assembly ("memory-safe") {
            quoteAmount := mload(add(reason, 0x24))
        }
    }
}
