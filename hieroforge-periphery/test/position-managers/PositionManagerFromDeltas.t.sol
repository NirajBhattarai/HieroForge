// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "hieroforge-core/PoolManager.sol";
import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {Currency} from "hieroforge-core/types/Currency.sol";
import {PositionInfo} from "../../src/types/PositionInfo.sol";
import {MockERC20} from "../utils/MockERC20.sol";

import {PositionManager} from "../../src/PositionManager.sol";
import {IPositionManager} from "../../src/interfaces/IPositionManager.sol";
import {Actions} from "../../src/libraries/Actions.sol";
import {MockHTS} from "../mocks/MockHTS.sol";

/// @notice Tests for FROM_DELTAS actions and settlement actions in PositionManager.
contract PositionManagerFromDeltasTest is Test {
    IPoolManager public manager;
    PositionManager public lpm;

    address constant HTS_PRECOMPILE = address(0x167);
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    PoolKey internal key;
    MockERC20 internal token0;
    MockERC20 internal token1;

    function setUp() public {
        manager = new PoolManager();
        MockHTS mockHts = new MockHTS();
        vm.etch(HTS_PRECOMPILE, address(mockHts).code);
        lpm = new PositionManager(manager);

        token0 = new MockERC20();
        token1 = new MockERC20();
        token0.mint(address(this), 10e18);
        token1.mint(address(this), 10e18);

        address a0 = address(token0);
        address a1 = address(token1);
        Currency c0 = a0 < a1 ? Currency.wrap(a0) : Currency.wrap(a1);
        Currency c1 = a0 < a1 ? Currency.wrap(a1) : Currency.wrap(a0);

        key = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: address(0)});
        manager.initialize(key, SQRT_PRICE_1_1);

        // Fund the position manager for existing (auto-settle) operations
        uint256 fundAmount = 2e18;
        (a0 < a1 ? token0 : token1).transfer(address(lpm), fundAmount);
        (a0 < a1 ? token1 : token0).transfer(address(lpm), fundAmount);

        // Approve the position manager so it can pull tokens via transferFrom (for FROM_DELTAS + SETTLE)
        (a0 < a1 ? token0 : token1).approve(address(lpm), type(uint256).max);
        (a0 < a1 ? token1 : token0).approve(address(lpm), type(uint256).max);
    }

    // ─── MINT_POSITION_FROM_DELTAS + SETTLE_PAIR ─────────────────────────────

    function test_mintFromDeltas_with_settlePair() public {
        address owner = address(this);
        uint256 liquidity = 1000;

        // Batch: [MINT_POSITION_FROM_DELTAS, SETTLE_PAIR]
        // The mint creates debt (PM owes tokens to PM core). SETTLE_PAIR pulls from user to pay.
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION_FROM_DELTAS), uint8(Actions.SETTLE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            key,
            int24(-60),
            int24(60),
            liquidity,
            uint128(type(uint128).max),
            uint128(type(uint128).max),
            owner,
            bytes("")
        );
        params[1] = abi.encode(key.currency0, key.currency1);

        bytes memory unlockData = abi.encode(actions, params);

        assertEq(lpm.nextTokenId(), 1, "nextTokenId before");
        lpm.modifyLiquidities(unlockData, block.timestamp + 1);

        assertEq(lpm.nextTokenId(), 2, "nextTokenId after");
        assertEq(lpm.ownerOf(1), owner, "owner of position");
        assertEq(lpm.positionLiquidity(1), uint128(liquidity), "position liquidity tracked");
    }

    function test_mintFromDeltas_with_closeCurrency() public {
        address owner = address(this);
        uint256 liquidity = 500;

        // Batch: [MINT_POSITION_FROM_DELTAS, CLOSE_CURRENCY(c0), CLOSE_CURRENCY(c1)]
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION_FROM_DELTAS), uint8(Actions.CLOSE_CURRENCY), uint8(Actions.CLOSE_CURRENCY)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            key,
            int24(-120),
            int24(120),
            liquidity,
            uint128(type(uint128).max),
            uint128(type(uint128).max),
            owner,
            bytes("")
        );
        params[1] = abi.encode(key.currency0);
        params[2] = abi.encode(key.currency1);

        bytes memory unlockData = abi.encode(actions, params);
        lpm.modifyLiquidities(unlockData, block.timestamp + 1);

        assertEq(lpm.nextTokenId(), 2, "position minted");
        assertEq(lpm.ownerOf(1), owner, "owner correct");
    }

    // ─── INCREASE_LIQUIDITY_FROM_DELTAS + SETTLE_PAIR ────────────────────────

    function test_increaseFromDeltas_with_settlePair() public {
        // First: mint a position normally (PM has funds from setUp)
        bytes memory mintActions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory mintParams = new bytes[](1);
        mintParams[0] = abi.encode(
            key,
            int24(-60),
            int24(60),
            uint256(1000),
            uint128(type(uint128).max),
            uint128(type(uint128).max),
            address(this),
            bytes("")
        );
        lpm.modifyLiquidities(abi.encode(mintActions, mintParams), block.timestamp + 1);
        assertEq(lpm.positionLiquidity(1), 1000, "initial liquidity");

        // Now: increase from deltas + settle pair (uses transferFrom from user)
        bytes memory actions =
            abi.encodePacked(uint8(Actions.INCREASE_LIQUIDITY_FROM_DELTAS), uint8(Actions.SETTLE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] =
            abi.encode(uint256(1), uint256(500), uint128(type(uint128).max), uint128(type(uint128).max), bytes(""));
        params[1] = abi.encode(key.currency0, key.currency1);

        lpm.modifyLiquidities(abi.encode(actions, params), block.timestamp + 1);
        assertEq(lpm.positionLiquidity(1), 1500, "liquidity increased");
    }

    // ─── Compose: DECREASE → INCREASE_FROM_DELTAS (reuse credits) ────────────

    function test_decrease_then_increaseFromDeltas_reusesCredits() public {
        // Mint two positions to the same range with different token IDs
        bytes memory actions1 = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory p1 = new bytes[](1);
        p1[0] = abi.encode(
            key,
            int24(-60),
            int24(60),
            uint256(2000),
            uint128(type(uint128).max),
            uint128(type(uint128).max),
            address(this),
            bytes("")
        );
        lpm.modifyLiquidities(abi.encode(actions1, p1), block.timestamp + 1);

        bytes memory actions2 = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory p2 = new bytes[](1);
        p2[0] = abi.encode(
            key,
            int24(-120),
            int24(120),
            uint256(500),
            uint128(type(uint128).max),
            uint128(type(uint128).max),
            address(this),
            bytes("")
        );
        lpm.modifyLiquidities(abi.encode(actions2, p2), block.timestamp + 1);

        assertEq(lpm.positionLiquidity(1), 2000);
        assertEq(lpm.positionLiquidity(2), 500);

        // Compose: decrease pos1 by 500, increase pos2 from deltas, then close remaining
        bytes memory composeActions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY),
            uint8(Actions.INCREASE_LIQUIDITY_FROM_DELTAS),
            uint8(Actions.CLOSE_CURRENCY),
            uint8(Actions.CLOSE_CURRENCY)
        );
        bytes[] memory composeParams = new bytes[](4);
        composeParams[0] = abi.encode(uint256(1), uint256(500), uint128(0), uint128(0), bytes(""));
        composeParams[1] =
            abi.encode(uint256(2), uint256(200), uint128(type(uint128).max), uint128(type(uint128).max), bytes(""));
        composeParams[2] = abi.encode(key.currency0);
        composeParams[3] = abi.encode(key.currency1);

        lpm.modifyLiquidities(abi.encode(composeActions, composeParams), block.timestamp + 1);

        assertEq(lpm.positionLiquidity(1), 1500, "pos1 decreased");
        assertEq(lpm.positionLiquidity(2), 700, "pos2 increased from deltas");
    }

    // ─── Settlement actions on PositionManager ───────────────────────────────

    function test_pm_settle_and_take_explicit() public {
        // Mint from deltas + explicit SETTLE and TAKE
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION_FROM_DELTAS),
            uint8(Actions.SETTLE),
            uint8(Actions.SETTLE),
            uint8(Actions.TAKE_PAIR)
        );
        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(
            key,
            int24(-60),
            int24(60),
            uint256(800),
            uint128(type(uint128).max),
            uint128(type(uint128).max),
            address(this),
            bytes("")
        );
        // SETTLE(currency0, amount=0=OPEN_DELTA, payerIsUser=true)
        params[1] = abi.encode(key.currency0, uint256(0), true);
        // SETTLE(currency1, amount=0=OPEN_DELTA, payerIsUser=true)
        params[2] = abi.encode(key.currency1, uint256(0), true);
        // TAKE_PAIR — take any remaining credits (should be empty, but safe)
        params[3] = abi.encode(key.currency0, key.currency1, address(this));

        lpm.modifyLiquidities(abi.encode(actions, params), block.timestamp + 1);

        assertEq(lpm.nextTokenId(), 2);
        assertEq(lpm.ownerOf(1), address(this));
    }

    function test_pm_takePair_after_decrease() public {
        // Mint normally
        bytes memory mintActions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory mintParams = new bytes[](1);
        mintParams[0] = abi.encode(
            key,
            int24(-60),
            int24(60),
            uint256(2000),
            uint128(type(uint128).max),
            uint128(type(uint128).max),
            address(this),
            bytes("")
        );
        lpm.modifyLiquidities(abi.encode(mintActions, mintParams), block.timestamp + 1);

        // Decrease has its own auto-take, but we can also use TAKE_PAIR on the remaining zero deltas
        // This just tests the flow doesn't revert
        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(uint256(1), uint256(500), uint128(0), uint128(0), bytes(""));
        // TAKE_PAIR on any remaining credits — should be zero since decrease already takes
        params[1] = abi.encode(key.currency0, key.currency1, address(this));

        lpm.modifyLiquidities(abi.encode(actions, params), block.timestamp + 1);

        assertEq(lpm.positionLiquidity(1), 1500);
    }
}
