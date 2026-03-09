// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Currency} from "hieroforge-core/types/Currency.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {IV4Router} from "../interfaces/IV4Router.sol";

/// @title Library for abi decoding of calldata
library CalldataDecoder {
    using CalldataDecoder for bytes;

    /// @notice mask used for offsets and lengths to ensure no overflow
    /// @dev no sane abi encoding will pass in an offset or length greater than type(uint32).max
    ///      (note that this does deviate from standard solidity behavior and offsets/lengths will
    ///      be interpreted as mod type(uint32).max which will only impact malicious/buggy callers)
    uint256 constant OFFSET_OR_LENGTH_MASK = 0xffffffff;
    uint256 constant OFFSET_OR_LENGTH_MASK_AND_WORD_ALIGN = 0xffffffe0;

    /// @notice equivalent to SliceOutOfBounds.selector, stored in least-significant bits
    uint256 constant SLICE_ERROR_SELECTOR = 0x3b99b53d;

    /// @dev equivalent to: abi.decode(params, (bytes, bytes[])) in calldata (requires strict abi encoding)
    function decodeActionsRouterParams(bytes calldata _bytes)
        internal
        pure
        returns (bytes calldata actions, bytes[] calldata params)
    {
        assembly ("memory-safe") {
            // Strict encoding requires that the data begin with:
            // 0x00: 0x40 (offset to `actions.length`)
            // 0x20: 0x60 + actions.length (offset to `params.length`)
            // 0x40: `actions.length`
            // 0x60: beginning of actions

            // Verify actions offset matches strict encoding
            let invalidData := xor(calldataload(_bytes.offset), 0x40)
            actions.offset := add(_bytes.offset, 0x60)
            actions.length := and(calldataload(add(_bytes.offset, 0x40)), OFFSET_OR_LENGTH_MASK)

            // Round actions length up to be word-aligned, and add 0x60 (for the first 3 words of encoding)
            let paramsLengthOffset := add(and(add(actions.length, 0x1f), OFFSET_OR_LENGTH_MASK_AND_WORD_ALIGN), 0x60)
            // Verify params offset matches strict encoding
            invalidData := or(invalidData, xor(calldataload(add(_bytes.offset, 0x20)), paramsLengthOffset))
            let paramsLengthPointer := add(_bytes.offset, paramsLengthOffset)
            params.length := and(calldataload(paramsLengthPointer), OFFSET_OR_LENGTH_MASK)
            params.offset := add(paramsLengthPointer, 0x20)

            // Expected offset for `params[0]` is params.length * 32
            // As the first `params.length` slots are pointers to each of the array element lengths
            let tailOffset := shl(5, params.length)
            let expectedOffset := tailOffset

            for { let offset := 0 } lt(offset, tailOffset) { offset := add(offset, 32) } {
                let itemLengthOffset := calldataload(add(params.offset, offset))
                // Verify that the offset matches the expected offset from strict encoding
                invalidData := or(invalidData, xor(itemLengthOffset, expectedOffset))
                let itemLengthPointer := add(params.offset, itemLengthOffset)
                let length :=
                    add(and(add(calldataload(itemLengthPointer), 0x1f), OFFSET_OR_LENGTH_MASK_AND_WORD_ALIGN), 0x20)
                expectedOffset := add(expectedOffset, length)
            }

            // if the data encoding was invalid, or the provided bytes string isnt as long as the encoding says, revert
            if or(invalidData, lt(add(_bytes.length, _bytes.offset), add(params.offset, expectedOffset))) {
                mstore(0, SLICE_ERROR_SELECTOR)
                revert(0x1c, 4)
            }
        }
    }

    function decodeModifyLiquidityParams(bytes calldata params)
        internal
        pure
        returns (uint256 tokenId, uint256 liquidity, uint128 amount0, uint128 amount1, bytes calldata hookData)
    {
        // no length check performed, as there is a length check in `toBytes`
        assembly ("memory-safe") {
            tokenId := calldataload(params.offset)
            liquidity := calldataload(add(params.offset, 0x20))
            amount0 := calldataload(add(params.offset, 0x40))
            amount1 := calldataload(add(params.offset, 0x60))
        }

        hookData = params.toBytes(4);
    }

    /// @notice Decode mint position params: PoolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, owner, hookData
    function decodeMintParams(bytes calldata params)
        internal
        pure
        returns (
            PoolKey memory poolKey,
            int24 tickLower,
            int24 tickUpper,
            uint256 liquidity,
            uint128 amount0Max,
            uint128 amount1Max,
            address owner,
            bytes calldata hookData
        )
    {
        bytes memory buf = new bytes(352);
        assembly ("memory-safe") {
            calldatacopy(add(buf, 32), params.offset, 352)
        }
        (poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, owner) =
            abi.decode(buf, (PoolKey, int24, int24, uint256, uint128, uint128, address));
        hookData = params.toBytes(11);
    }

    /// @dev equivalent to: abi.decode(params, (IV4Router.ExactInputSingleParams)) in calldata
    function decodeSwapExactInSingleParams(bytes calldata params)
        internal
        pure
        returns (IV4Router.ExactInputSingleParams calldata swapParams)
    {
        assembly ("memory-safe") {
            if lt(params.length, 0x140) {
                mstore(0, SLICE_ERROR_SELECTOR)
                revert(0x1c, 4)
            }
            swapParams := add(params.offset, calldataload(params.offset))
        }
    }

    /// @dev equivalent to: abi.decode(params, (IV4Router.ExactOutputSingleParams)) in calldata
    function decodeSwapExactOutSingleParams(bytes calldata params)
        internal
        pure
        returns (IV4Router.ExactOutputSingleParams calldata swapParams)
    {
        assembly ("memory-safe") {
            if lt(params.length, 0x140) {
                mstore(0, SLICE_ERROR_SELECTOR)
                revert(0x1c, 4)
            }
            swapParams := add(params.offset, calldataload(params.offset))
        }
    }

    /// @dev equivalent to: abi.decode(params, (Currency, uint256)) in calldata
    function decodeCurrencyAndUint256(bytes calldata params) internal pure returns (Currency currency, uint256 amount) {
        assembly ("memory-safe") {
            if lt(params.length, 0x40) {
                mstore(0, SLICE_ERROR_SELECTOR)
                revert(0x1c, 4)
            }
            currency := calldataload(params.offset)
            amount := calldataload(add(params.offset, 0x20))
        }
    }

    /// @notice Decode the `_arg`-th element in `_bytes` as `bytes`
    /// @param _bytes The input bytes string to extract a bytes string from
    /// @param _arg The index of the argument to extract
    function toBytes(bytes calldata _bytes, uint256 _arg) internal pure returns (bytes calldata res) {
        uint256 length;
        assembly ("memory-safe") {
            // The offset of the `_arg`-th element is `32 * arg`, which stores the offset of the length pointer.
            // shl(5, x) is equivalent to mul(32, x)
            let lengthPtr :=
                add(_bytes.offset, and(calldataload(add(_bytes.offset, shl(5, _arg))), OFFSET_OR_LENGTH_MASK))
            // the number of bytes in the bytes string
            length := and(calldataload(lengthPtr), OFFSET_OR_LENGTH_MASK)
            // the offset where the bytes string begins
            let offset := add(lengthPtr, 0x20)
            // assign the return parameters
            res.length := length
            res.offset := offset

            // if the provided bytes string isnt as long as the encoding says, revert
            if lt(add(_bytes.length, _bytes.offset), add(length, offset)) {
                mstore(0, SLICE_ERROR_SELECTOR)
                revert(0x1c, 4)
            }
        }
    }
}
