// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "hieroforge-core/PoolManager.sol";
import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
import {Router} from "hieroforge-core-test/utils/Router.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {PoolId} from "hieroforge-core/types/PoolId.sol";
import {Currency} from "hieroforge-core/types/Currency.sol";
import {ModifyLiquidityParams} from "hieroforge-core/types/ModifyLiquidityParams.sol";
import {TickMath} from "hieroforge-core/libraries/TickMath.sol";
import {IERC20} from "hedera-forking/IERC20.sol";
import {htsSetup} from "hedera-forking/htsSetup.sol";
import {IHederaTokenService} from "hedera-forking/IHederaTokenService.sol";
import {HederaResponseCodes} from "hedera-forking/HederaResponseCodes.sol";

import {UniversalRouter} from "../src/UniversalRouter.sol";
import {PositionManager} from "../src/PositionManager.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {Commands} from "../src/libraries/Commands.sol";
import {Actions} from "../src/libraries/Actions.sol";
import {IV4Router} from "../src/interfaces/IV4Router.sol";
import {PathKey} from "../src/libraries/PathKey.sol";

/// @notice Multi-hop swap tests and settlement action tests.
/// Run: forge test --match-contract V4RouterMultiHopTest --ffi -vvv
contract V4RouterMultiHopTest is Test {
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    int24 internal constant TICK_SPACING = 60;

    IPoolManager public manager;
    Router public router;
    UniversalRouter public universalRouter;

    Currency internal currA;
    Currency internal currB;
    Currency internal currC;

    PoolKey internal keyAB;
    PoolKey internal keyBC;

    function setUp() public {
        manager = new PoolManager();
        router = new Router(manager);

        htsSetup();
        vm.deal(address(this), 1 ether);
        address hts = address(0x167);

        // Create 3 HTS tokens
        address tokenA = _createHtsToken(hts, "TokenA", "TKA");
        address tokenB = _createHtsToken(hts, "TokenB", "TKB");
        address tokenC = _createHtsToken(hts, "TokenC", "TKC");

        // Sort to get proper currency ordering
        address[] memory sorted = _sort3(tokenA, tokenB, tokenC);
        currA = Currency.wrap(sorted[0]);
        currB = Currency.wrap(sorted[1]);
        currC = Currency.wrap(sorted[2]);

        // Ensure balances
        _ensureTreasuryBalance(sorted[0], 10_000_000_000);
        _ensureTreasuryBalance(sorted[1], 10_000_000_000);
        _ensureTreasuryBalance(sorted[2], 10_000_000_000);

        // Approve router
        IERC20(sorted[0]).approve(address(router), type(uint256).max);
        IERC20(sorted[1]).approve(address(router), type(uint256).max);
        IERC20(sorted[2]).approve(address(router), type(uint256).max);

        // Initialize pool A-B
        keyAB = PoolKey({currency0: currA, currency1: currB, fee: 3000, tickSpacing: TICK_SPACING, hooks: address(0)});
        manager.initialize(keyAB, SQRT_PRICE_1_1);

        // Initialize pool B-C
        keyBC = PoolKey({currency0: currB, currency1: currC, fee: 3000, tickSpacing: TICK_SPACING, hooks: address(0)});
        manager.initialize(keyBC, SQRT_PRICE_1_1);

        // Add liquidity to both pools
        uint256 fundAmount = 3e9;
        IERC20(sorted[0]).transfer(address(router), fundAmount);
        IERC20(sorted[1]).transfer(address(router), fundAmount);
        router.modifyLiquidity(
            keyAB,
            ModifyLiquidityParams({
                tickLower: -180, tickUpper: 180, liquidityDelta: int256(uint256(1e9)), salt: bytes32(0)
            }),
            ""
        );

        IERC20(sorted[1]).transfer(address(router), fundAmount);
        IERC20(sorted[2]).transfer(address(router), fundAmount);
        router.modifyLiquidity(
            keyBC,
            ModifyLiquidityParams({
                tickLower: -180, tickUpper: 180, liquidityDelta: int256(uint256(1e9)), salt: bytes32(0)
            }),
            ""
        );

        // Deploy UniversalRouter
        PositionManager pm = new PositionManager(manager);
        universalRouter = new UniversalRouter(manager, IPositionManager(address(pm)));

        // Approve universal router
        IERC20(sorted[0]).approve(address(universalRouter), type(uint256).max);
        IERC20(sorted[1]).approve(address(universalRouter), type(uint256).max);
        IERC20(sorted[2]).approve(address(universalRouter), type(uint256).max);
    }

    // ─── Multi-hop exact input: A → B → C ───────────────────────────────────

    function test_swapExactInput_multiHop_AtoC() public {
        uint128 amountIn = 100_000;
        uint128 minAmountOut = 80_000;

        address tokenA = Currency.unwrap(currA);
        address tokenC = Currency.unwrap(currC);
        uint256 balABefore = IERC20(tokenA).balanceOf(address(this));
        uint256 balCBefore = IERC20(tokenC).balanceOf(address(this));

        // Path: A → B → C (2 hops)
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currB, fee: 3000, tickSpacing: TICK_SPACING, hooks: address(0), hookData: ""
        });
        path[1] = PathKey({
            intermediateCurrency: currC, fee: 3000, tickSpacing: TICK_SPACING, hooks: address(0), hookData: ""
        });

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputParams({
                currencyIn: currA, path: path, amountIn: amountIn, amountOutMinimum: minAmountOut
            })
        );
        params[1] = abi.encode(currA, uint256(amountIn));
        params[2] = abi.encode(currC, uint256(minAmountOut));

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        universalRouter.execute(commands, inputs, block.timestamp + 60);

        assertEq(IERC20(tokenA).balanceOf(address(this)), balABefore - amountIn, "token A spent");
        assertGe(IERC20(tokenC).balanceOf(address(this)), balCBefore + minAmountOut, "token C received >= min");
    }

    function test_swapExactInput_multiHop_CtoA() public {
        uint128 amountIn = 100_000;
        uint128 minAmountOut = 80_000;

        address tokenA = Currency.unwrap(currA);
        address tokenC = Currency.unwrap(currC);
        uint256 balABefore = IERC20(tokenA).balanceOf(address(this));
        uint256 balCBefore = IERC20(tokenC).balanceOf(address(this));

        // Path: C → B → A (2 hops, reverse direction)
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currB, fee: 3000, tickSpacing: TICK_SPACING, hooks: address(0), hookData: ""
        });
        path[1] = PathKey({
            intermediateCurrency: currA, fee: 3000, tickSpacing: TICK_SPACING, hooks: address(0), hookData: ""
        });

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputParams({
                currencyIn: currC, path: path, amountIn: amountIn, amountOutMinimum: minAmountOut
            })
        );
        params[1] = abi.encode(currC, uint256(amountIn));
        params[2] = abi.encode(currA, uint256(minAmountOut));

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        universalRouter.execute(commands, inputs, block.timestamp + 60);

        assertEq(IERC20(tokenC).balanceOf(address(this)), balCBefore - amountIn, "token C spent");
        assertGe(IERC20(tokenA).balanceOf(address(this)), balABefore + minAmountOut, "token A received >= min");
    }

    // ─── Multi-hop exact output: A → B → C ──────────────────────────────────

    function test_swapExactOutput_multiHop_AtoC() public {
        uint128 amountOut = 90_000;
        uint128 maxAmountIn = 120_000;

        address tokenA = Currency.unwrap(currA);
        address tokenC = Currency.unwrap(currC);
        uint256 balABefore = IERC20(tokenA).balanceOf(address(this));
        uint256 balCBefore = IERC20(tokenC).balanceOf(address(this));

        // Path for exact output: reversed — [{intermediate: A}, {intermediate: B}]
        // Backward loop: i=2 → pool(B,C) via pathKey{B}+outputCurrency=C; i=1 → pool(A,B) via pathKey{A}+outputCurrency=B
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currA, fee: 3000, tickSpacing: TICK_SPACING, hooks: address(0), hookData: ""
        });
        path[1] = PathKey({
            intermediateCurrency: currB, fee: 3000, tickSpacing: TICK_SPACING, hooks: address(0), hookData: ""
        });

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactOutputParams({
                currencyOut: currC, path: path, amountOut: amountOut, amountInMaximum: maxAmountIn
            })
        );
        params[1] = abi.encode(currA, uint256(maxAmountIn));
        params[2] = abi.encode(currC, uint256(amountOut));

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        universalRouter.execute(commands, inputs, block.timestamp + 60);

        assertEq(IERC20(tokenC).balanceOf(address(this)), balCBefore + amountOut, "token C received exact");
        assertLe(balABefore - IERC20(tokenA).balanceOf(address(this)), maxAmountIn, "token A spent <= max");
    }

    // ─── Multi-hop slippage reverts ──────────────────────────────────────────

    function test_swapExactInput_multiHop_revertsWhenMinAmountOutNotMet() public {
        uint128 amountIn = 100_000;
        uint128 minAmountOut = 200_000; // impossible

        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currB, fee: 3000, tickSpacing: TICK_SPACING, hooks: address(0), hookData: ""
        });
        path[1] = PathKey({
            intermediateCurrency: currC, fee: 3000, tickSpacing: TICK_SPACING, hooks: address(0), hookData: ""
        });

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputParams({
                currencyIn: currA, path: path, amountIn: amountIn, amountOutMinimum: minAmountOut
            })
        );
        params[1] = abi.encode(currA, uint256(amountIn));
        params[2] = abi.encode(currC, uint256(minAmountOut));

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        vm.expectRevert();
        universalRouter.execute(commands, inputs, block.timestamp + 60);
    }

    function test_swapExactOutput_multiHop_revertsWhenAmountInExceedsMax() public {
        uint128 amountOut = 90_000;
        uint128 maxAmountIn = 10; // way too low

        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currB, fee: 3000, tickSpacing: TICK_SPACING, hooks: address(0), hookData: ""
        });
        path[1] = PathKey({
            intermediateCurrency: currC, fee: 3000, tickSpacing: TICK_SPACING, hooks: address(0), hookData: ""
        });

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactOutputParams({
                currencyOut: currC, path: path, amountOut: amountOut, amountInMaximum: maxAmountIn
            })
        );
        params[1] = abi.encode(currA, uint256(maxAmountIn));
        params[2] = abi.encode(currC, uint256(amountOut));

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        vm.expectRevert();
        universalRouter.execute(commands, inputs, block.timestamp + 60);
    }

    // ─── Settlement action tests (SETTLE, TAKE, SETTLE_PAIR, TAKE_PAIR, CLOSE_CURRENCY) ──

    function test_settlement_settle_and_take_explicit() public {
        uint128 amountIn = 100_000;

        // Single-hop swap with explicit SETTLE + TAKE instead of SETTLE_ALL + TAKE_ALL
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE), uint8(Actions.TAKE));
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: keyAB, zeroForOne: true, amountIn: amountIn, amountOutMinimum: 0, hookData: ""
            })
        );
        // SETTLE: (currency, amount=0 means OPEN_DELTA, payerIsUser=true)
        params[1] = abi.encode(currA, uint256(0), true);
        // TAKE: (currency, recipient=MSG_SENDER, amount=0 means OPEN_DELTA)
        params[2] = abi.encode(currB, address(1), uint256(0)); // address(1) = MSG_SENDER

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        address tokenB = Currency.unwrap(currB);
        uint256 balBBefore = IERC20(tokenB).balanceOf(address(this));

        universalRouter.execute(commands, inputs, block.timestamp + 60);

        assertGt(IERC20(tokenB).balanceOf(address(this)), balBBefore, "token B received via TAKE");
    }

    function test_settlement_settlePair_and_takePair() public {
        uint128 amountIn = 100_000;

        // Single-hop swap then close both currencies with SETTLE_PAIR + TAKE_PAIR
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_PAIR), uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: keyAB, zeroForOne: true, amountIn: amountIn, amountOutMinimum: 0, hookData: ""
            })
        );
        params[1] = abi.encode(currA, currB); // SETTLE_PAIR(currA, currB)
        params[2] = abi.encode(currA, currB, address(1)); // TAKE_PAIR(currA, currB, MSG_SENDER)

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        address tokenB = Currency.unwrap(currB);
        uint256 balBBefore = IERC20(tokenB).balanceOf(address(this));

        universalRouter.execute(commands, inputs, block.timestamp + 60);

        assertGt(IERC20(tokenB).balanceOf(address(this)), balBBefore, "token B received via TAKE_PAIR");
    }

    function test_settlement_closeCurrency() public {
        uint128 amountIn = 100_000;

        // Swap then close both currencies using CLOSE_CURRENCY
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.CLOSE_CURRENCY), uint8(Actions.CLOSE_CURRENCY)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: keyAB, zeroForOne: true, amountIn: amountIn, amountOutMinimum: 0, hookData: ""
            })
        );
        params[1] = abi.encode(currA); // CLOSE_CURRENCY(currA) — has debt, will settle
        params[2] = abi.encode(currB); // CLOSE_CURRENCY(currB) — has credit, will take

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        address tokenB = Currency.unwrap(currB);
        uint256 balBBefore = IERC20(tokenB).balanceOf(address(this));

        universalRouter.execute(commands, inputs, block.timestamp + 60);

        assertGt(IERC20(tokenB).balanceOf(address(this)), balBBefore, "token B received via CLOSE_CURRENCY");
    }

    // ─── Multi-hop with SETTLE_PAIR + TAKE_PAIR ──────────────────────────────

    function test_swapExactInput_multiHop_with_settlePair() public {
        uint128 amountIn = 100_000;
        uint128 minAmountOut = 80_000;

        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: currB, fee: 3000, tickSpacing: TICK_SPACING, hooks: address(0), hookData: ""
        });
        path[1] = PathKey({
            intermediateCurrency: currC, fee: 3000, tickSpacing: TICK_SPACING, hooks: address(0), hookData: ""
        });

        // Use SETTLE_PAIR + TAKE_PAIR for settlement instead of SETTLE_ALL + TAKE_ALL
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN), uint8(Actions.SETTLE_PAIR), uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputParams({
                currencyIn: currA, path: path, amountIn: amountIn, amountOutMinimum: minAmountOut
            })
        );
        params[1] = abi.encode(currA, currC);
        params[2] = abi.encode(currA, currC, address(1)); // MSG_SENDER

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        address tokenC = Currency.unwrap(currC);
        uint256 balCBefore = IERC20(tokenC).balanceOf(address(this));

        universalRouter.execute(commands, inputs, block.timestamp + 60);

        assertGe(IERC20(tokenC).balanceOf(address(this)), balCBefore + minAmountOut, "token C received >= min");
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    function _createHtsToken(address hts, string memory name, string memory symbol) internal returns (address) {
        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](0);
        IHederaTokenService.Expiry memory expiry = IHederaTokenService.Expiry(0, address(0), 0);
        IHederaTokenService.HederaToken memory token = IHederaTokenService.HederaToken({
            name: name,
            symbol: symbol,
            treasury: address(this),
            memo: "",
            tokenSupplyType: true,
            maxSupply: 20_000_000_000,
            freezeDefault: false,
            tokenKeys: keys,
            expiry: expiry
        });
        (int64 code, address addr) = IHederaTokenService(hts).createFungibleToken{value: 100}(token, 10_000_000_000, 18);
        require(code == int64(int32(22)) && addr != address(0), "HTS creation failed");
        return addr;
    }

    function _sort3(address a, address b, address c) internal pure returns (address[] memory sorted) {
        sorted = new address[](3);
        sorted[0] = a;
        sorted[1] = b;
        sorted[2] = c;
        // Simple bubble sort for 3 elements
        if (sorted[0] > sorted[1]) (sorted[0], sorted[1]) = (sorted[1], sorted[0]);
        if (sorted[1] > sorted[2]) (sorted[1], sorted[2]) = (sorted[2], sorted[1]);
        if (sorted[0] > sorted[1]) (sorted[0], sorted[1]) = (sorted[1], sorted[0]);
    }

    function _ensureTreasuryBalance(address token, uint256 amount) internal {
        uint32 accountId = uint32(bytes4(keccak256(abi.encodePacked(address(this)))));
        bytes32 balanceSlot = bytes32(abi.encodePacked(IERC20.balanceOf.selector, uint192(0), accountId));
        vm.store(token, balanceSlot, bytes32(amount));
    }
}
