// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {PoolId} from "hieroforge-core/types/PoolId.sol";
import {Currency} from "hieroforge-core/types/Currency.sol";
import {BalanceDelta} from "hieroforge-core/types/BalanceDelta.sol";
import {SwapParams} from "hieroforge-core/types/SwapParams.sol";
import {TickMath} from "hieroforge-core/libraries/TickMath.sol";
import {IERC20Minimal} from "hieroforge-core/interfaces/IERC20Minimal.sol";
import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
import {PoolKey, TokensMustBeSorted, InvalidTickSpacing} from "hieroforge-core/types/PoolKey.sol";
import {V4Quoter} from "../src/V4Quoter.sol";
import {IV4Quoter} from "../src/interfaces/IV4Quoter.sol";
import {QuoterRevert} from "../src/libraries/QuoterRevert.sol";
import {BaseV4Quoter} from "../src/base/BaseV4Quoter.sol";
import {PathKey} from "../src/libraries/PathKey.sol";
import {QuoterTestDeployers} from "./utils/QuoterTestDeployers.sol";

/// @notice V4Quoter tests using HTS tokens only. Run with: forge test --match-contract QuoterTest --ffi
///        Against local Hedera node: forge test --match-contract QuoterTest --ffi --fork-url http://localhost:7546
contract QuoterTest is Test, QuoterTestDeployers {
    V4Quoter public quoter;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2CurrenciesHTS();
        setupPoolWithLiquidity();
        quoter = new V4Quoter(manager);
    }

    function test_quoteExactInputSingle_zeroForOne() public {
        uint128 amountIn = 1000;
        IV4Quoter.QuoteExactSingleParams memory params =
            IV4Quoter.QuoteExactSingleParams({poolKey: key, zeroForOne: true, exactAmount: amountIn, hookData: ""});

        (uint256 amountOut, uint256 gasEstimate) = quoter.quoteExactInputSingle(params);
        assertGt(amountOut, 0, "amountOut should be positive");
        assertGe(amountOut, amountIn * 99 / 100, "amountOut >= amountIn minus fee");
        assertLe(amountOut, amountIn + 20, "amountOut ~ amountIn (with fee)");
        assertGt(gasEstimate, 0, "gasEstimate should be positive");
    }

    function test_quoteExactInputSingle_oneForZero() public {
        uint128 amountIn = 1000;
        IV4Quoter.QuoteExactSingleParams memory params =
            IV4Quoter.QuoteExactSingleParams({poolKey: key, zeroForOne: false, exactAmount: amountIn, hookData: ""});

        (uint256 amountOut, uint256 gasEstimate) = quoter.quoteExactInputSingle(params);
        assertGt(amountOut, 0, "amountOut should be positive");
        assertGe(amountOut, amountIn * 99 / 100, "amountOut >= amountIn minus fee");
        assertGt(gasEstimate, 0, "gasEstimate should be positive");
    }

    function test_quoteExactOutputSingle_zeroForOne() public {
        uint128 amountOutDesired = 500;
        IV4Quoter.QuoteExactSingleParams memory params = IV4Quoter.QuoteExactSingleParams({
            poolKey: key, zeroForOne: true, exactAmount: amountOutDesired, hookData: ""
        });

        (uint256 amountIn, uint256 gasEstimate) = quoter.quoteExactOutputSingle(params);
        assertGt(amountIn, 0, "amountIn should be positive");
        assertGe(amountIn, amountOutDesired, "amountIn >= amountOut");
        assertGt(gasEstimate, 0, "gasEstimate should be positive");
    }

    function test_quoteExactOutputSingle_oneForZero() public {
        uint128 amountOutDesired = 500;
        IV4Quoter.QuoteExactSingleParams memory params = IV4Quoter.QuoteExactSingleParams({
            poolKey: key, zeroForOne: false, exactAmount: amountOutDesired, hookData: ""
        });

        (uint256 amountIn, uint256 gasEstimate) = quoter.quoteExactOutputSingle(params);
        assertGt(amountIn, 0, "amountIn should be positive");
        assertGe(amountIn, amountOutDesired, "amountIn >= amountOut");
        assertGt(gasEstimate, 0, "gasEstimate should be positive");
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Edge cases: reverts
    // ─────────────────────────────────────────────────────────────────────────────

    function test_quoteExactInputSingle_revertsWhen_poolNotInitialized() public {
        PoolKey memory uninitializedKey = PoolKey({
            currency0: key.currency0,
            currency1: key.currency1,
            fee: 100,
            tickSpacing: key.tickSpacing,
            hooks: address(0)
        });
        IV4Quoter.QuoteExactSingleParams memory params = IV4Quoter.QuoteExactSingleParams({
            poolKey: uninitializedKey, zeroForOne: true, exactAmount: 1000, hookData: ""
        });
        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        quoter.quoteExactInputSingle(params);
    }

    function test_quoteExactOutputSingle_revertsWhen_poolNotInitialized() public {
        PoolKey memory uninitializedKey = PoolKey({
            currency0: key.currency0,
            currency1: key.currency1,
            fee: 100,
            tickSpacing: key.tickSpacing,
            hooks: address(0)
        });
        IV4Quoter.QuoteExactSingleParams memory params = IV4Quoter.QuoteExactSingleParams({
            poolKey: uninitializedKey, zeroForOne: true, exactAmount: 500, hookData: ""
        });
        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        quoter.quoteExactOutputSingle(params);
    }

    function test_quoteExactInputSingle_revertsWhen_zeroAmount() public {
        IV4Quoter.QuoteExactSingleParams memory params =
            IV4Quoter.QuoteExactSingleParams({poolKey: key, zeroForOne: true, exactAmount: 0, hookData: ""});
        vm.expectRevert(IPoolManager.SwapAmountCannotBeZero.selector);
        quoter.quoteExactInputSingle(params);
    }

    function test_quoteExactOutputSingle_revertsWhen_zeroAmount() public {
        IV4Quoter.QuoteExactSingleParams memory params =
            IV4Quoter.QuoteExactSingleParams({poolKey: key, zeroForOne: true, exactAmount: 0, hookData: ""});
        vm.expectRevert(IPoolManager.SwapAmountCannotBeZero.selector);
        quoter.quoteExactOutputSingle(params);
    }

    function test_quoteExactInputSingle_revertsWhen_notEnoughLiquidity() public {
        uint128 hugeAmountIn = 1e30;
        IV4Quoter.QuoteExactSingleParams memory params =
            IV4Quoter.QuoteExactSingleParams({poolKey: key, zeroForOne: true, exactAmount: hugeAmountIn, hookData: ""});
        vm.expectRevert(abi.encodeWithSelector(BaseV4Quoter.NotEnoughLiquidity.selector, key.toId()));
        quoter.quoteExactInputSingle(params);
    }

    function test_quoteExactOutputSingle_revertsWhen_notEnoughLiquidity() public {
        uint128 hugeAmountOut = type(uint128).max;
        IV4Quoter.QuoteExactSingleParams memory params = IV4Quoter.QuoteExactSingleParams({
            poolKey: key, zeroForOne: true, exactAmount: hugeAmountOut, hookData: ""
        });
        vm.expectRevert(abi.encodeWithSelector(BaseV4Quoter.NotEnoughLiquidity.selector, key.toId()));
        quoter.quoteExactOutputSingle(params);
    }

    function test_quoteExactInputSingle_revertsWhen_unsortedCurrencies() public {
        PoolKey memory badKey = PoolKey({
            currency0: key.currency1,
            currency1: key.currency0,
            fee: key.fee,
            tickSpacing: key.tickSpacing,
            hooks: key.hooks
        });
        IV4Quoter.QuoteExactSingleParams memory params =
            IV4Quoter.QuoteExactSingleParams({poolKey: badKey, zeroForOne: true, exactAmount: 1000, hookData: ""});
        vm.expectRevert(TokensMustBeSorted.selector);
        quoter.quoteExactInputSingle(params);
    }

    function test_quoteExactInputSingle_revertsWhen_invalidTickSpacing() public {
        PoolKey memory badKey = PoolKey({
            currency0: key.currency0, currency1: key.currency1, fee: key.fee, tickSpacing: 0, hooks: key.hooks
        });
        IV4Quoter.QuoteExactSingleParams memory params =
            IV4Quoter.QuoteExactSingleParams({poolKey: badKey, zeroForOne: true, exactAmount: 1000, hookData: ""});
        vm.expectRevert(InvalidTickSpacing.selector);
        quoter.quoteExactInputSingle(params);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Edge cases: small amounts and exact-output swap match
    // ─────────────────────────────────────────────────────────────────────────────

    function test_quoteExactInputSingle_smallAmount() public {
        IV4Quoter.QuoteExactSingleParams memory params =
            IV4Quoter.QuoteExactSingleParams({poolKey: key, zeroForOne: true, exactAmount: 1, hookData: ""});
        (uint256 amountOut,) = quoter.quoteExactInputSingle(params);
        assertGe(amountOut, 0, "amountOut >= 0 for 1 wei in");
    }

    function test_quoteExactOutputSingle_smallAmount() public {
        IV4Quoter.QuoteExactSingleParams memory params =
            IV4Quoter.QuoteExactSingleParams({poolKey: key, zeroForOne: true, exactAmount: 1, hookData: ""});
        (uint256 amountIn,) = quoter.quoteExactOutputSingle(params);
        assertGe(amountIn, 1, "amountIn >= 1 for 1 wei out");
    }

    /// @notice Quote and actual swap should match: exact-output quote amountIn, then swap and get at least amountOut
    function test_quoteMatchesSwap_exactOutput() public {
        uint128 amountOutDesired = 500;
        IV4Quoter.QuoteExactSingleParams memory params = IV4Quoter.QuoteExactSingleParams({
            poolKey: key, zeroForOne: true, exactAmount: amountOutDesired, hookData: ""
        });
        (uint256 quotedAmountIn,) = quoter.quoteExactOutputSingle(params);
        address token0 = Currency.unwrap(key.currency0);
        IERC20Minimal(token0).transfer(address(router), quotedAmountIn);
        SwapParams memory swapParams = SwapParams({
            amountSpecified: int256(uint256(amountOutDesired)),
            tickSpacing: key.tickSpacing,
            zeroForOne: true,
            sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
            lpFeeOverride: 0
        });
        BalanceDelta delta = router.swap(key, swapParams, "");
        uint256 actualOut = uint256(uint128(delta.amount1()));
        assertGe(actualOut, amountOutDesired, "swap should output at least desired amount");
    }

    /// @notice Quote and actual swap should match: exact-input quote amountOut equals swap result
    function test_quoteMatchesSwap_exactInput() public {
        uint128 amountIn = 1000;
        IV4Quoter.QuoteExactSingleParams memory params =
            IV4Quoter.QuoteExactSingleParams({poolKey: key, zeroForOne: true, exactAmount: amountIn, hookData: ""});

        (uint256 quotedAmountOut,) = quoter.quoteExactInputSingle(params);

        address token0 = Currency.unwrap(key.currency0);
        IERC20Minimal(token0).transfer(address(router), amountIn);

        SwapParams memory swapParams = SwapParams({
            amountSpecified: -int256(uint256(amountIn)),
            tickSpacing: key.tickSpacing,
            zeroForOne: true,
            sqrtPriceLimitX96: TickMath.minSqrtPrice() + 1,
            lpFeeOverride: 0
        });

        BalanceDelta delta = router.swap(key, swapParams, "");
        uint256 actualOut =
            swapParams.zeroForOne ? uint256(uint128(delta.amount1())) : uint256(uint128(delta.amount0()));

        assertEq(quotedAmountOut, actualOut, "quote should match actual swap output");
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Gas estimate
    // ─────────────────────────────────────────────────────────────────────────────

    function test_quoteExactInputSingle_returnsGasEstimate() public {
        IV4Quoter.QuoteExactSingleParams memory params =
            IV4Quoter.QuoteExactSingleParams({poolKey: key, zeroForOne: true, exactAmount: 1000, hookData: ""});
        (, uint256 gasEstimate) = quoter.quoteExactInputSingle(params);
        assertGt(gasEstimate, 0, "gas estimate should be non-zero");
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // msgSender tracking
    // ─────────────────────────────────────────────────────────────────────────────

    function test_msgSender_returnsZeroOutsideQuote() public view {
        assertEq(quoter.msgSender(), address(0), "msgSender should be zero outside quote");
    }
}
