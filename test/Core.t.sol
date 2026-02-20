// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {htsSetup} from "hedera-forking/htsSetup.sol";
import {HTS_ADDRESS} from "hedera-forking/HtsSystemContract.sol";
import {IHederaTokenService} from "hedera-forking/IHederaTokenService.sol";
import {HederaResponseCodes} from "hedera-forking/HederaResponseCodes.sol";
import {Core} from "../src/Core.sol";
import {ICore} from "../src/interfaces/ICore.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {Currency} from "../src/types/Currency.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {MIN_TICK_SPACING, MAX_TICK_SPACING} from "../src/math/constants.sol";

/**
 * Tests for Core using HTS (Hedera Token Service) tokens only.
 * Requires --ffi; use --fork-url for mirror node if needed.
 */
contract CoreTest is Test {
    Core public core;
    address internal signer;
    address internal tokenA;
    address internal tokenB;

    function setUp() external {
        htsSetup();
        core = new Core();
        signer = makeAddr("signer");
        vm.deal(signer, 100 ether);

        tokenA = _createHTSToken("Token A", "TKA");
        tokenB = _createHTSToken("Token B", "TKB");
    }

    function _createHTSToken(string memory name, string memory symbol) internal returns (address) {
        IHederaTokenService.KeyValue memory keyValue;
        keyValue.inheritAccountKey = true;

        IHederaTokenService.HederaToken memory token;
        token.name = name;
        token.symbol = symbol;
        token.treasury = signer;
        token.memo = "";
        token.tokenKeys = new IHederaTokenService.TokenKey[](2);
        token.tokenKeys[0] = IHederaTokenService.TokenKey(0x1, keyValue);
        token.tokenKeys[1] = IHederaTokenService.TokenKey(0x10, keyValue);
        token.expiry = IHederaTokenService.Expiry(0, signer, 8000000);

        vm.prank(signer);
        (int64 responseCode, address tokenAddress) =
            IHederaTokenService(HTS_ADDRESS).createFungibleToken{value: 10 ether}(token, 1e18, 18);

        require(responseCode == HederaResponseCodes.SUCCESS, "createFungibleToken failed");
        require(tokenAddress != address(0), "token address zero");
        return tokenAddress;
    }

    function _validPoolKey() internal view returns (PoolKey memory key) {
        (Currency t0, Currency t1) = tokenA < tokenB
            ? (Currency.wrap(tokenA), Currency.wrap(tokenB))
            : (Currency.wrap(tokenB), Currency.wrap(tokenA));
        key.token0 = t0;
        key.token1 = t1;
        key.fee = 3000;
        key.tickSpacing = 60;
        key.hooks = IHooks(address(0));
    }

    function test_initialize_revertWhenTickSpacingTooSmall() external {
        PoolKey memory key = _validPoolKey();
        key.tickSpacing = 0;

        vm.expectRevert(abi.encodeWithSelector(ICore.TickSpacingTooSmall.selector, int24(0)));
        core.initialize(key, 1);
    }

    function test_initialize_revertWhenTickSpacingTooSmall_negative() external {
        PoolKey memory key = _validPoolKey();
        key.tickSpacing = -1;

        vm.expectRevert(abi.encodeWithSelector(ICore.TickSpacingTooSmall.selector, int24(-1)));
        core.initialize(key, 1);
    }

    function test_initialize_revertWhenTickSpacingTooLarge() external {
        PoolKey memory key = _validPoolKey();
        key.tickSpacing = int24(int256(type(int16).max) + 1);

        vm.expectRevert(abi.encodeWithSelector(ICore.TickSpacingTooLarge.selector, key.tickSpacing));
        core.initialize(key, 1);
    }

    function test_initialize_revertWhenCurrenciesOutOfOrder() external {
        PoolKey memory key = _validPoolKey();
        key.token0 = Currency.wrap(tokenB);
        key.token1 = Currency.wrap(tokenA);

        vm.expectRevert(abi.encodeWithSelector(ICore.CurrenciesOutOfOrderOrEqual.selector, tokenB, tokenA));
        core.initialize(key, 1);
    }

    function test_initialize_revertWhenCurrenciesEqual() external {
        PoolKey memory key = _validPoolKey();
        key.token0 = Currency.wrap(tokenA);
        key.token1 = Currency.wrap(tokenA);

        vm.expectRevert(abi.encodeWithSelector(ICore.CurrenciesOutOfOrderOrEqual.selector, tokenA, tokenA));
        core.initialize(key, 1);
    }

    function test_initialize_success() external {
        PoolKey memory key = _validPoolKey();
        uint160 sqrtPriceX96 = 79228162514264337593543950336;

        int24 tick = core.initialize(key, sqrtPriceX96);

        assertEq(tick, 0);
    }

    function test_initialize_success_minTickSpacing() external {
        PoolKey memory key = _validPoolKey();
        key.tickSpacing = MIN_TICK_SPACING;

        int24 tick = core.initialize(key, 1);
        assertEq(tick, 0);
    }

    function test_initialize_success_maxTickSpacing() external {
        PoolKey memory key = _validPoolKey();
        key.tickSpacing = MAX_TICK_SPACING;

        int24 tick = core.initialize(key, 1);
        assertEq(tick, 0);
    }
}
