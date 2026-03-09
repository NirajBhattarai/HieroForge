// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {Currency} from "hieroforge-core/types/Currency.sol";
import {IERC20} from "hedera-forking/IERC20.sol";
import {UniversalRouter} from "../src/UniversalRouter.sol";
import {Commands} from "../src/libraries/Commands.sol";
import {Actions} from "../src/libraries/Actions.sol";
import {IV4Router} from "../src/interfaces/IV4Router.sol";
import {IUniversalRouter} from "../src/interfaces/IUniversalRouter.sol";
import {QuoterTestDeployers} from "./utils/QuoterTestDeployers.sol";

/// @notice V4Router swap tests using HTS tokens (single-hop exact-in and exact-out).
/// Run (mock/fork): forge test --match-contract V4RouterSwapTest --ffi
/// Run against local HTS node: forge test --match-contract V4RouterSwapTest --ffi --fork-url http://localhost:7546
/// (Requires a running Hedera local node at localhost:7546; see foundry.toml rpc_endpoints.local)
contract V4RouterSwapTest is Test, QuoterTestDeployers {
    UniversalRouter public universalRouter;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2CurrenciesHTS();
        setupPoolWithLiquidity();
        universalRouter = new UniversalRouter(manager);
        // Test contract is the execute() caller; SETTLE_ALL pays from msgSender() so we approve universalRouter to pull from this
        IERC20(Currency.unwrap(currency0)).approve(address(universalRouter), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(universalRouter), type(uint256).max);
    }

    function test_swapExactInputSingle_zeroForOne() public {
        uint128 amountIn = 100_000;
        uint128 minAmountOut = 90_000; // allow ~10% slippage
        address token0Addr = Currency.unwrap(currency0);
        address token1Addr = Currency.unwrap(currency1);
        uint256 bal0Before = IERC20(token0Addr).balanceOf(address(this));
        uint256 bal1Before = IERC20(token1Addr).balanceOf(address(this));

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                hookData: ""
            })
        );
        params[1] = abi.encode(currency0, amountIn);
        params[2] = abi.encode(currency1, minAmountOut);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        uint256 deadline = block.timestamp + 60;

        universalRouter.execute(commands, inputs, deadline);

        assertEq(IERC20(token0Addr).balanceOf(address(this)), bal0Before - amountIn, "token0 spent");
        assertGe(IERC20(token1Addr).balanceOf(address(this)), bal1Before + minAmountOut, "token1 received >= min");
    }

    function test_swapExactInputSingle_oneForZero() public {
        uint128 amountIn = 100_000;
        uint128 minAmountOut = 90_000;
        address token0Addr = Currency.unwrap(currency0);
        address token1Addr = Currency.unwrap(currency1);
        uint256 bal0Before = IERC20(token0Addr).balanceOf(address(this));
        uint256 bal1Before = IERC20(token1Addr).balanceOf(address(this));

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: false,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                hookData: ""
            })
        );
        params[1] = abi.encode(currency1, amountIn);
        params[2] = abi.encode(currency0, minAmountOut);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        uint256 deadline = block.timestamp + 60;

        universalRouter.execute(commands, inputs, deadline);

        assertEq(IERC20(token1Addr).balanceOf(address(this)), bal1Before - amountIn, "token1 spent");
        assertGe(IERC20(token0Addr).balanceOf(address(this)), bal0Before + minAmountOut, "token0 received >= min");
    }

    function test_swapExactOutputSingle_zeroForOne() public {
        uint128 amountOut = 95_000;
        uint128 amountInMaximum = 120_000;
        address token0Addr = Currency.unwrap(currency0);
        address token1Addr = Currency.unwrap(currency1);
        uint256 bal0Before = IERC20(token0Addr).balanceOf(address(this));
        uint256 bal1Before = IERC20(token1Addr).balanceOf(address(this));

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_OUT_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum,
                hookData: ""
            })
        );
        params[1] = abi.encode(currency0, amountInMaximum);
        params[2] = abi.encode(currency1, amountOut);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        uint256 deadline = block.timestamp + 60;

        universalRouter.execute(commands, inputs, deadline);

        assertEq(IERC20(token1Addr).balanceOf(address(this)), bal1Before + amountOut, "token1 received exact");
        assertLe(IERC20(token0Addr).balanceOf(address(this)), bal0Before - 90_000, "token0 spent (approx)");
        assertGe(bal0Before - IERC20(token0Addr).balanceOf(address(this)), 90_000, "token0 spent at least ~amountOut");
    }

    function test_swapExactOutputSingle_oneForZero() public {
        uint128 amountOut = 95_000;
        uint128 amountInMaximum = 120_000;
        address token0Addr = Currency.unwrap(currency0);
        address token1Addr = Currency.unwrap(currency1);
        uint256 bal0Before = IERC20(token0Addr).balanceOf(address(this));
        uint256 bal1Before = IERC20(token1Addr).balanceOf(address(this));

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_OUT_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: key,
                zeroForOne: false,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum,
                hookData: ""
            })
        );
        params[1] = abi.encode(currency1, amountInMaximum);
        params[2] = abi.encode(currency0, amountOut);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        uint256 deadline = block.timestamp + 60;

        universalRouter.execute(commands, inputs, deadline);

        assertEq(IERC20(token0Addr).balanceOf(address(this)), bal0Before + amountOut, "token0 received exact");
        assertLe(IERC20(token1Addr).balanceOf(address(this)), bal1Before - 90_000, "token1 spent (approx)");
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Edge cases: slippage and validation reverts
    // ─────────────────────────────────────────────────────────────────────────────

    /// @dev Exact-in: minAmountOut set higher than possible output → V4TooLittleReceived (wrapped in ExecutionFailed)
    function test_swapExactInputSingle_revertsWhenMinAmountOutNotMet() public {
        uint128 amountIn = 100_000;
        uint128 minAmountOut = 200_000; // impossible: we put in 100k, want at least 200k out

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                hookData: ""
            })
        );
        params[1] = abi.encode(currency0, amountIn);
        params[2] = abi.encode(currency1, minAmountOut);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        uint256 deadline = block.timestamp + 60;

        vm.expectRevert();
        universalRouter.execute(commands, inputs, deadline);
    }

    /// @dev Exact-out: amountInMaximum too low for requested amountOut → V4TooMuchRequested (wrapped in ExecutionFailed)
    function test_swapExactOutputSingle_revertsWhenAmountInExceedsMaximum() public {
        uint128 amountOut = 95_000;
        uint128 amountInMaximum = 10; // way too low to get 95k out

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_OUT_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum,
                hookData: ""
            })
        );
        params[1] = abi.encode(currency0, amountInMaximum);
        params[2] = abi.encode(currency1, amountOut);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        uint256 deadline = block.timestamp + 60;

        vm.expectRevert();
        universalRouter.execute(commands, inputs, deadline);
    }

    /// @dev SETTLE_ALL: maxAmount lower than actual debt → V4TooMuchRequested
    function test_swapExactInputSingle_revertsWhenSettleMaxTooLow() public {
        uint128 amountIn = 100_000;
        uint128 minAmountOut = 90_000;
        uint256 settleMax = 50_000; // we owe amountIn (100k) but only allow 50k

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                hookData: ""
            })
        );
        params[1] = abi.encode(currency0, settleMax); // SETTLE_ALL(currency0, 50k) but debt is 100k
        params[2] = abi.encode(currency1, minAmountOut);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        uint256 deadline = block.timestamp + 60;

        vm.expectRevert();
        universalRouter.execute(commands, inputs, deadline);
    }

    /// @dev TAKE_ALL: minAmount higher than actual credit → V4TooLittleReceived
    function test_swapExactInputSingle_revertsWhenTakeMinTooHigh() public {
        uint128 amountIn = 100_000;
        uint128 minAmountOut = 90_000;
        uint256 takeMin = 200_000; // we receive ~99k but require at least 200k

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                hookData: ""
            })
        );
        params[1] = abi.encode(currency0, amountIn);
        params[2] = abi.encode(currency1, takeMin); // TAKE_ALL(currency1, 200k) but credit is ~99k

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        uint256 deadline = block.timestamp + 60;

        vm.expectRevert();
        universalRouter.execute(commands, inputs, deadline);
    }

    /// @dev execute() reverts when deadline has passed
    function test_execute_revertsWhenDeadlinePassed() public {
        uint128 amountIn = 100_000;
        uint128 minAmountOut = 90_000;
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                hookData: ""
            })
        );
        params[1] = abi.encode(currency0, amountIn);
        params[2] = abi.encode(currency1, minAmountOut);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        uint256 deadline = block.timestamp - 1;

        vm.expectRevert(IUniversalRouter.TransactionDeadlinePassed.selector);
        universalRouter.execute(commands, inputs, deadline);
    }

    /// @dev execute() reverts when commands.length != inputs.length
    function test_execute_revertsWhenCommandsLengthMismatch() public {
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(bytes(""), new bytes[](0));
        inputs[1] = abi.encode(bytes(""), new bytes[](0));
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP)); // length 1

        vm.expectRevert(IUniversalRouter.LengthMismatch.selector);
        universalRouter.execute(commands, inputs, block.timestamp + 60);
    }

    /// @dev Unsupported action byte in unlock payload → UnsupportedAction (wrapped in ExecutionFailed)
    function test_unsupportedAction_reverts() public {
        bytes memory actions = abi.encodePacked(uint8(0xff)); // invalid action
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(currency0, uint256(0));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        uint256 deadline = block.timestamp + 60;

        vm.expectRevert();
        universalRouter.execute(commands, inputs, deadline);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Edge cases: small amounts and zero minimum
    // ─────────────────────────────────────────────────────────────────────────────

    /// @dev minAmountOut = 0: swap should succeed and accept any output
    function test_swapExactInputSingle_zeroMinAmountOut_succeeds() public {
        uint128 amountIn = 50_000;
        uint128 minAmountOut = 0;
        address token0Addr = Currency.unwrap(currency0);
        address token1Addr = Currency.unwrap(currency1);
        uint256 bal0Before = IERC20(token0Addr).balanceOf(address(this));
        uint256 bal1Before = IERC20(token1Addr).balanceOf(address(this));

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                hookData: ""
            })
        );
        params[1] = abi.encode(currency0, amountIn);
        params[2] = abi.encode(currency1, minAmountOut);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        uint256 deadline = block.timestamp + 60;

        universalRouter.execute(commands, inputs, deadline);

        assertEq(IERC20(token0Addr).balanceOf(address(this)), bal0Before - amountIn, "token0 spent");
        assertGt(IERC20(token1Addr).balanceOf(address(this)), bal1Before, "token1 received");
    }

    /// @dev Small amountIn: ensures no rounding/underflow issues
    function test_swapExactInputSingle_smallAmount_succeeds() public {
        uint128 amountIn = 100;
        uint128 minAmountOut = 50;
        address token1Addr = Currency.unwrap(currency1);
        uint256 bal1Before = IERC20(token1Addr).balanceOf(address(this));

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                hookData: ""
            })
        );
        params[1] = abi.encode(currency0, amountIn);
        params[2] = abi.encode(currency1, minAmountOut);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        uint256 deadline = block.timestamp + 60;

        universalRouter.execute(commands, inputs, deadline);

        assertGe(IERC20(token1Addr).balanceOf(address(this)), bal1Before + minAmountOut, "token1 received >= min");
    }

    /// @dev Exact-out with tight amountInMaximum: should still succeed if pool has enough liquidity
    function test_swapExactOutputSingle_tightAmountInMaximum_succeeds() public {
        uint128 amountOut = 50_000;
        uint128 amountInMaximum = 60_000; // tight but achievable
        address token0Addr = Currency.unwrap(currency0);
        address token1Addr = Currency.unwrap(currency1);
        uint256 bal0Before = IERC20(token0Addr).balanceOf(address(this));
        uint256 bal1Before = IERC20(token1Addr).balanceOf(address(this));

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_OUT_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum,
                hookData: ""
            })
        );
        params[1] = abi.encode(currency0, amountInMaximum);
        params[2] = abi.encode(currency1, amountOut);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        uint256 deadline = block.timestamp + 60;

        universalRouter.execute(commands, inputs, deadline);

        assertEq(IERC20(token1Addr).balanceOf(address(this)), bal1Before + amountOut, "token1 received exact");
        assertLe(bal0Before - IERC20(token0Addr).balanceOf(address(this)), amountInMaximum, "token0 spent <= max");
    }
}
