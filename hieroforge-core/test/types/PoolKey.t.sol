// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PoolKey, TokensMustBeSorted, InvalidTickSpacing} from "../../src/types/PoolKey.sol";
import {Currency} from "../../src/types/Currency.sol";
import {PoolId} from "../../src/types/PoolId.sol";
import {MIN_TICK_SPACING, MAX_TICK_SPACING} from "../../src/constants.sol";

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

    function test_Validate_SucceedsWhenCurrenciesSorted() public view {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        validator.validateKey(key); // should not revert
    }

    function test_RevertWhen_Validate_TickSpacingBelowMin() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 3000,
            tickSpacing: MIN_TICK_SPACING - 1,
            hooks: address(0)
        });
        vm.expectRevert(InvalidTickSpacing.selector);
        validator.validateKey(key);
    }

    function test_RevertWhen_Validate_TickSpacingAboveMax() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 3000,
            tickSpacing: MAX_TICK_SPACING + 1,
            hooks: address(0)
        });
        vm.expectRevert(InvalidTickSpacing.selector);
        validator.validateKey(key);
    }

    function test_Validate_SucceedsAtMinAndMaxTickSpacing() public view {
        PoolKey memory keyMin = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 3000,
            tickSpacing: MIN_TICK_SPACING,
            hooks: address(0)
        });
        validator.validateKey(keyMin);

        PoolKey memory keyMax = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 3000,
            tickSpacing: MAX_TICK_SPACING,
            hooks: address(0)
        });
        validator.validateKey(keyMax);
    }

    function test_ToId_SameKeyReturnsSamePoolId() public pure {
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

    function test_ToId_DifferentKeysReturnDifferentPoolIds() public pure {
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

    function test_ToId_DifferentFieldProducesDifferentId() public pure {
        PoolKey memory base = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        PoolId idBase = base.toId();

        PoolKey memory keyDiffTick = PoolKey({
            currency0: base.currency0, currency1: base.currency1, fee: base.fee, tickSpacing: 1, hooks: base.hooks
        });
        assertTrue(PoolId.unwrap(idBase) != PoolId.unwrap(keyDiffTick.toId()), "tickSpacing");

        PoolKey memory keyDiffHooks = PoolKey({
            currency0: base.currency0,
            currency1: base.currency1,
            fee: base.fee,
            tickSpacing: base.tickSpacing,
            hooks: address(0xBeef)
        });
        assertTrue(PoolId.unwrap(idBase) != PoolId.unwrap(keyDiffHooks.toId()), "hooks");

        PoolKey memory keyDiffCurr0 = PoolKey({
            currency0: Currency.wrap(address(0x0)),
            currency1: base.currency1,
            fee: base.fee,
            tickSpacing: base.tickSpacing,
            hooks: base.hooks
        });
        assertTrue(PoolId.unwrap(idBase) != PoolId.unwrap(keyDiffCurr0.toId()), "currency0");

        PoolKey memory keyDiffCurr1 = PoolKey({
            currency0: base.currency0,
            currency1: Currency.wrap(address(0x3)),
            fee: base.fee,
            tickSpacing: base.tickSpacing,
            hooks: base.hooks
        });
        assertTrue(PoolId.unwrap(idBase) != PoolId.unwrap(keyDiffCurr1.toId()), "currency1");
    }

    function test_ToId_DeterministicFromEncoding() public pure {
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
