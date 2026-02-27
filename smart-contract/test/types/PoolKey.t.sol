// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PoolKey, TokensMustBeSorted} from "../../src/types/PoolKey.sol";
import {Currency} from "../../src/types/Currency.sol";
import {PoolId} from "../../src/types/PoolId.sol";

/// @notice Helper to trigger PoolKey.validate() via an external call so expectRevert works
contract PoolKeyValidator {
    function validateKey(PoolKey memory key) external pure {
        key.validate();
    }
}

contract PoolKeyTest is Test {
    PoolKeyValidator public validator;

    function setUp() public {
        validator = new PoolKeyValidator();
    }

    function test_RevertWhen_Validate_Currency0GreaterThanCurrency1() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x2)),
            currency1: Currency.wrap(address(0x1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        vm.expectRevert(TokensMustBeSorted.selector);
        validator.validateKey(key);
    }

    function test_RevertWhen_Validate_Currency0EqualsCurrency1() public {
        address same = address(0x100);
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(same),
            currency1: Currency.wrap(same),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        vm.expectRevert(TokensMustBeSorted.selector);
        validator.validateKey(key);
    }

    function test_Validate_SucceedsWhenCurrenciesSorted() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        validator.validateKey(key); // should not revert
    }

    function test_ToId_SameKeyReturnsSamePoolId() public view {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        PoolId id0 = key.toId();
        PoolId id1 = key.toId();
        assertEq(PoolId.unwrap(id0), PoolId.unwrap(id1));
    }

    function test_ToId_DifferentKeysReturnDifferentPoolIds() public view {
        PoolKey memory keyA = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        PoolKey memory keyB = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 5000,
            tickSpacing: 60,
            hooks: address(0)
        });
        PoolId idA = keyA.toId();
        PoolId idB = keyB.toId();
        assertTrue(PoolId.unwrap(idA) != PoolId.unwrap(idB));
    }

    function test_ToId_DeterministicFromEncoding() public view {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0xA)),
            currency1: Currency.wrap(address(0xB)),
            fee: 10000,
            tickSpacing: -60,
            hooks: address(0xC)
        });
        PoolId id = key.toId();
        assertEq(PoolId.unwrap(id), keccak256(abi.encode(key)));
    }
}
