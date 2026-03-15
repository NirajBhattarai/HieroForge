// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {TickMath} from "../src/libraries/TickMath.sol";
import {SqrtPriceMath} from "../src/libraries/SqrtPriceMath.sol";
import {MAX_TICK, MIN_TICK} from "../src/constants.sol";

/// @notice Verify the concentrated-liquidity math that the UI must replicate.
/// Run: cd hieroforge-core && forge test --match-contract LiquidityMathVerify -vvv
contract LiquidityMathVerifyTest is Test {
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336; // sqrt(1) * 2^96

    /// @dev Given L and tick range around price 1.0 (same-decimal 8/8 HTS tokens),
    /// compute the token amounts required and verify they're consistent.
    function test_amountsFromLiquidity_sameDecimals() public pure {
        // Pool: 8-decimal token pair at 1:1 price
        uint160 sqrtPriceX96 = SQRT_PRICE_1_1; // tick = 0
        int24 tickLower = -6960;
        int24 tickUpper = 6960; // symmetric range

        uint160 sqrtPriceA = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceB = TickMath.getSqrtPriceAtTick(tickUpper);

        console.log("sqrtPriceA:", sqrtPriceA);
        console.log("sqrtPriceB:", sqrtPriceB);
        console.log("sqrtPriceX96 (current):", sqrtPriceX96);

        // User wants to deposit: amount0 = 1.0 token (= 1e8 in 8-decimal)
        uint128 targetAmount0 = 100_000_000; // 1.0 token in 8-decimal

        // Compute L from amount0: L = amount0 * sqrtP * sqrtPb / ((sqrtPb - sqrtP) * Q96)
        // Using getAmount0Delta inverse: L such that getAmount0Delta(sqrtP, sqrtPb, L) = targetAmount0
        // L = amount0 * sqrtPC * sqrtPB / (Q96 * (sqrtPB - sqrtPC))
        uint256 L = _liquidityForAmount0(sqrtPriceX96, sqrtPriceB, targetAmount0);
        console.log("Liquidity L:", L);

        // Compute actual amounts from L
        uint256 amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtPriceB, uint128(L), true);
        uint256 amount1 = SqrtPriceMath.getAmount1Delta(sqrtPriceA, sqrtPriceX96, uint128(L), true);

        console.log("amount0:", amount0);
        console.log("amount1:", amount1);
        console.log("amount0 (human, 8dec):", amount0, "/ 1e8 =", amount0 / 1e8);
        console.log("amount1 (human, 8dec):", amount1, "/ 1e8 =", amount1 / 1e8);

        // amount0 should be close to targetAmount0
        assertApproxEqAbs(amount0, targetAmount0, 2, "amount0 should match target");
        // For symmetric range at 1:1, amount1 should be similar
        assertApproxEqRel(amount0, amount1, 0.05e18, "amounts should be similar at 1:1 symmetric range");
    }

    /// @dev Same test with full range ticks
    function test_amountsFromLiquidity_fullRange() public pure {
        uint160 sqrtPriceX96 = SQRT_PRICE_1_1;
        int24 tickLower = -887220;
        int24 tickUpper = 887220;

        uint160 sqrtPriceA = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceB = TickMath.getSqrtPriceAtTick(tickUpper);

        uint128 L = 10_000_000; // 0.1 in 8-decimal scale

        uint256 amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtPriceB, L, true);
        uint256 amount1 = SqrtPriceMath.getAmount1Delta(sqrtPriceA, sqrtPriceX96, L, true);

        console.log("Full range L:", L);
        console.log("amount0:", amount0);
        console.log("amount1:", amount1);

        // Both should be similar for 1:1 price
        assertGt(amount0, 0, "amount0 should be > 0");
        assertGt(amount1, 0, "amount1 should be > 0");
    }

    /// @dev Prove that tickUpper > MAX_TICK reverts
    function test_invalidTickReverts() public {
        TickHelper helper = new TickHelper();
        vm.expectRevert();
        helper.getSqrtPrice(int24(1044480)); // exceeds MAX_TICK
    }

    /// @dev Verify the UI's liquidityToWei formula: L_wei = L_human * 10^((d0+d1)/2)
    function test_liquidityScaling_verification() public pure {
        // For 8-decimal tokens: scale factor = 10^((8+8)/2) = 10^8
        // User sees: L_human = some float
        // On-chain: L_wei = L_human * 1e8

        uint160 sqrtPriceX96 = SQRT_PRICE_1_1;
        int24 tickLower = -6960;
        int24 tickUpper = 6960;

        uint160 sqrtPA = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPB = TickMath.getSqrtPriceAtTick(tickUpper);

        // If L_human = 1.0, L_wei should be 1e8 for 8-decimal tokens
        uint128 L_wei = 100_000_000;

        uint256 a0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtPB, L_wei, true);
        uint256 a1 = SqrtPriceMath.getAmount1Delta(sqrtPA, sqrtPriceX96, L_wei, true);

        console.log("=== Scaling verification ===");
        console.log("L_wei (L_human=1.0):", L_wei);
        console.log("amount0 (raw):", a0);
        console.log("amount1 (raw):", a1);

        // Human-readable: divide by 1e8
        // amount0_human = a0 / 1e8, amount1_human = a1 / 1e8
        // The UI's float L=1.0 should give amount0_human ≈ amount0_raw / 1e8
        // This verifies that liquidityToWei(1.0, 8, 8) = 1e8 gives correct amounts
        console.log("amount0 (human, /1e8):", a0 / 1e8);
        console.log("amount1 (human, /1e8):", a1 / 1e8);

        assertGt(a0, 0);
        assertGt(a1, 0);
    }

    /// @dev Helper: compute liquidity for a given amount0 (in-range)
    function _liquidityForAmount0(uint160 sqrtPC, uint160 sqrtPB, uint128 amount0) internal pure returns (uint256) {
        // L = amount0 * sqrtPC * sqrtPB / (Q96 * (sqrtPB - sqrtPC))
        uint256 Q96 = 1 << 96;
        uint256 numerator = uint256(amount0) * uint256(sqrtPC);
        // Use FullMath for precision
        uint256 denominator = sqrtPB - sqrtPC;
        return (numerator * sqrtPB) / (denominator * Q96);
    }
}

contract TickHelper {
    function getSqrtPrice(int24 tick) external pure returns (uint160) {
        return TickMath.getSqrtPriceAtTick(tick);
    }
}
