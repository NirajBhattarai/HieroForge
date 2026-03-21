// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "hieroforge-core/PoolManager.sol";
import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {Currency} from "hieroforge-core/types/Currency.sol";

import {PositionManager} from "../../src/PositionManager.sol";
import {IPositionManager} from "../../src/interfaces/IPositionManager.sol";
import {IERC721Permit_v4} from "../../src/interfaces/IERC721Permit_v4.sol";
import {Actions} from "../../src/libraries/Actions.sol";
import {Hsc} from "hedera-forking/Hsc.sol";
import {MockERC20} from "../utils/MockERC20.sol";

/// @notice Broad edge-case coverage for PositionManager (mint / increase / decrease / burn, auth, slippage, deadlines).
/// @dev Uses the same Hedera HTS setup + local PoolManager pattern as PositionManagerFromDeltasTest.
contract PositionManagerEdgeCasesTest is Test {
    IPoolManager public manager;
    PositionManager public lpm;

    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    PoolKey internal key;
    MockERC20 internal token0;
    MockERC20 internal token1;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        Hsc.htsSetup();
        manager = new PoolManager();
        lpm = new PositionManager(manager);

        token0 = new MockERC20();
        token1 = new MockERC20();
        token0.mint(address(this), 100e18);
        token1.mint(address(this), 100e18);
        token0.mint(alice, 50e18);
        token1.mint(alice, 50e18);
        token0.mint(bob, 50e18);
        token1.mint(bob, 50e18);

        address a0 = address(token0);
        address a1 = address(token1);
        Currency c0 = a0 < a1 ? Currency.wrap(a0) : Currency.wrap(a1);
        Currency c1 = a0 < a1 ? Currency.wrap(a1) : Currency.wrap(a0);

        key = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: address(0)});
        manager.initialize(key, SQRT_PRICE_1_1);

        uint256 fundAmount = 20e18;
        (a0 < a1 ? token0 : token1).transfer(address(lpm), fundAmount);
        (a0 < a1 ? token1 : token0).transfer(address(lpm), fundAmount);

        (a0 < a1 ? token0 : token1).approve(address(lpm), type(uint256).max);
        (a0 < a1 ? token1 : token0).approve(address(lpm), type(uint256).max);

        vm.startPrank(alice);
        (a0 < a1 ? token0 : token1).approve(address(lpm), type(uint256).max);
        (a0 < a1 ? token1 : token0).approve(address(lpm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        (a0 < a1 ? token0 : token1).approve(address(lpm), type(uint256).max);
        (a0 < a1 ? token1 : token0).approve(address(lpm), type(uint256).max);
        vm.stopPrank();
    }

    function _modify(bytes memory actions, bytes[] memory params) internal {
        lpm.modifyLiquidities(abi.encode(actions, params), block.timestamp + 1000);
    }

    function _modifyDeadline(bytes memory actions, bytes[] memory params, uint256 deadline) internal {
        lpm.modifyLiquidities(abi.encode(actions, params), deadline);
    }

    function _mint(address owner, int24 tl, int24 tu, uint256 liq, uint128 a0max, uint128 a1max) internal {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(key, tl, tu, liq, a0max, a1max, owner, bytes(""));
        vm.prank(owner);
        _modify(actions, params);
    }

    function _mintThis(int24 tl, int24 tu, uint256 liq) internal {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory params = new bytes[](1);
        params[0] =
            abi.encode(key, tl, tu, liq, type(uint128).max, type(uint128).max, address(this), bytes(""));
        _modify(actions, params);
    }

    // ── Mint / IDs / liquidity tracking ─────────────────────────────────────

    function test_edge_mint_tracks_liquidity_and_owner() public {
        assertEq(lpm.nextTokenId(), 1);
        _mintThis(-60, 60, 1000);
        assertEq(lpm.nextTokenId(), 2);
        assertEq(lpm.ownerOf(1), address(this));
        assertEq(lpm.positionLiquidity(1), 1000);
    }

    function test_edge_two_mints_same_range_increment_token_ids() public {
        _mintThis(-60, 60, 500);
        _mintThis(-60, 60, 700);
        assertEq(lpm.ownerOf(1), address(this));
        assertEq(lpm.ownerOf(2), address(this));
        assertEq(lpm.positionLiquidity(1), 500);
        assertEq(lpm.positionLiquidity(2), 700);
        assertEq(lpm.nextTokenId(), 3);
    }

    function test_edge_two_mints_different_ranges() public {
        _mintThis(-120, 120, 400);
        _mintThis(-240, 240, 600);
        assertEq(lpm.positionLiquidity(1), 400);
        assertEq(lpm.positionLiquidity(2), 600);
    }

    function test_edge_mint_to_alice_owner_not_caller() public {
        vm.prank(alice);
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(
            key, int24(-60), int24(60), uint256(800), type(uint128).max, type(uint128).max, alice, bytes("")
        );
        _modify(actions, params);
        assertEq(lpm.ownerOf(1), alice);
        assertEq(lpm.positionLiquidity(1), 800);
    }

    function test_edge_small_liquidity_mint() public {
        _mintThis(-60, 60, 1);
        assertEq(lpm.positionLiquidity(1), 1);
    }

    // ── Increase / decrease ───────────────────────────────────────────────────

    function test_edge_increase_updates_tracked_liquidity() public {
        _mintThis(-60, 60, 1000);
        bytes memory actions = abi.encodePacked(uint8(Actions.INCREASE_LIQUIDITY));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), uint256(250), type(uint128).max, type(uint128).max, bytes(""));
        _modify(actions, params);
        assertEq(lpm.positionLiquidity(1), 1250);
    }

    function test_edge_decrease_partial() public {
        _mintThis(-60, 60, 2000);
        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), uint256(700), uint128(0), uint128(0), bytes(""));
        _modify(actions, params);
        assertEq(lpm.positionLiquidity(1), 1300);
    }

    function test_edge_two_partial_decreases_then_burn() public {
        _mintThis(-60, 60, 1000);
        bytes memory a1 = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
        bytes[] memory p1 = new bytes[](1);
        p1[0] = abi.encode(uint256(1), uint256(400), uint128(0), uint128(0), bytes(""));
        _modify(a1, p1);
        bytes memory a2 = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
        bytes[] memory p2 = new bytes[](1);
        p2[0] = abi.encode(uint256(1), uint256(300), uint128(0), uint128(0), bytes(""));
        _modify(a2, p2);
        assertEq(lpm.positionLiquidity(1), 300);
        bytes memory a3 = abi.encodePacked(uint8(Actions.BURN_POSITION));
        bytes[] memory p3 = new bytes[](1);
        p3[0] = abi.encode(uint256(1), uint128(0), uint128(0), bytes(""));
        _modify(a3, p3);
        vm.expectRevert();
        lpm.ownerOf(1);
    }

    function test_edge_increase_then_decrease_net_positive() public {
        _mintThis(-60, 60, 500);
        bytes memory inc = abi.encodePacked(uint8(Actions.INCREASE_LIQUIDITY));
        bytes[] memory pi = new bytes[](1);
        pi[0] = abi.encode(uint256(1), uint256(200), type(uint128).max, type(uint128).max, bytes(""));
        _modify(inc, pi);
        bytes memory dec = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
        bytes[] memory pd = new bytes[](1);
        pd[0] = abi.encode(uint256(1), uint256(100), uint128(0), uint128(0), bytes(""));
        _modify(dec, pd);
        assertEq(lpm.positionLiquidity(1), 600);
    }

    function test_edge_decrease_zero_liquidity_no_state_change() public {
        _mintThis(-60, 60, 100);
        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), uint256(0), uint128(0), uint128(0), bytes(""));
        _modify(actions, params);
        assertEq(lpm.positionLiquidity(1), 100);
    }

    function test_edge_increase_zero_liquidity_no_liquidity_change() public {
        _mintThis(-60, 60, 50);
        bytes memory actions = abi.encodePacked(uint8(Actions.INCREASE_LIQUIDITY));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), uint256(0), type(uint128).max, type(uint128).max, bytes(""));
        _modify(actions, params);
        assertEq(lpm.positionLiquidity(1), 50);
    }

    // ── Burn (including auto-remove remaining liquidity) ──────────────────────

    function test_edge_burn_clears_remaining_liquidity_in_one_call() public {
        _mintThis(-60, 60, 1500);
        bytes memory actions = abi.encodePacked(uint8(Actions.BURN_POSITION));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), uint128(0), uint128(0), bytes(""));
        _modify(actions, params);
        vm.expectRevert();
        lpm.ownerOf(1);
    }

    function test_edge_mint_decrease_all_then_burn_same_unlock() public {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION), uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.BURN_POSITION)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            key, int24(-60), int24(60), uint256(400), type(uint128).max, type(uint128).max, address(this), bytes("")
        );
        params[1] = abi.encode(uint256(1), uint256(400), uint128(0), uint128(0), bytes(""));
        params[2] = abi.encode(uint256(1), uint128(0), uint128(0), bytes(""));
        _modify(actions, params);
        assertEq(lpm.nextTokenId(), 2);
        vm.expectRevert();
        lpm.ownerOf(1);
    }

    function test_edge_burn_two_positions_sequentially() public {
        _mintThis(-60, 60, 100);
        _mintThis(-120, 120, 200);
        bytes memory b1 = abi.encodePacked(uint8(Actions.BURN_POSITION));
        bytes[] memory p1 = new bytes[](1);
        p1[0] = abi.encode(uint256(1), uint128(0), uint128(0), bytes(""));
        _modify(b1, p1);
        bytes memory b2 = abi.encodePacked(uint8(Actions.BURN_POSITION));
        bytes[] memory p2 = new bytes[](1);
        p2[0] = abi.encode(uint256(2), uint128(0), uint128(0), bytes(""));
        _modify(b2, p2);
        vm.expectRevert();
        lpm.ownerOf(1);
        vm.expectRevert();
        lpm.ownerOf(2);
    }

    function test_edge_double_burn_reverts() public {
        _mintThis(-60, 60, 10);
        bytes memory actions = abi.encodePacked(uint8(Actions.BURN_POSITION));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), uint128(0), uint128(0), bytes(""));
        _modify(actions, params);
        vm.expectRevert();
        _modify(actions, params);
    }

    // ── Authorization ─────────────────────────────────────────────────────────

    function test_edge_unauthorized_cannot_decrease() public {
        _mint(alice, -60, 60, 1000, type(uint128).max, type(uint128).max);
        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), uint256(100), uint128(0), uint128(0), bytes(""));
        vm.expectRevert(IERC721Permit_v4.Unauthorized.selector);
        _modify(actions, params);
    }

    function test_edge_unauthorized_cannot_increase() public {
        _mint(alice, -60, 60, 500, type(uint128).max, type(uint128).max);
        bytes memory actions = abi.encodePacked(uint8(Actions.INCREASE_LIQUIDITY));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), uint256(50), type(uint128).max, type(uint128).max, bytes(""));
        vm.expectRevert(IERC721Permit_v4.Unauthorized.selector);
        _modify(actions, params);
    }

    function test_edge_unauthorized_cannot_burn() public {
        _mint(alice, -60, 60, 200, type(uint128).max, type(uint128).max);
        bytes memory actions = abi.encodePacked(uint8(Actions.BURN_POSITION));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), uint128(0), uint128(0), bytes(""));
        vm.expectRevert(IERC721Permit_v4.Unauthorized.selector);
        _modify(actions, params);
    }

    function test_edge_getApproved_spender_can_decrease() public {
        _mint(alice, -60, 60, 800, type(uint128).max, type(uint128).max);
        vm.prank(alice);
        lpm.approve(bob, 1);
        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), uint256(200), uint128(0), uint128(0), bytes(""));
        vm.prank(bob);
        _modify(actions, params);
        assertEq(lpm.positionLiquidity(1), 600);
    }

    function test_edge_setApprovalForAll_operator_can_burn() public {
        _mint(alice, -60, 60, 300, type(uint128).max, type(uint128).max);
        vm.prank(alice);
        lpm.setApprovalForAll(bob, true);
        bytes memory actions = abi.encodePacked(uint8(Actions.BURN_POSITION));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), uint128(0), uint128(0), bytes(""));
        vm.prank(bob);
        _modify(actions, params);
        vm.expectRevert();
        lpm.ownerOf(1);
    }

    function test_edge_revoke_approval_blocks_decrease() public {
        _mint(alice, -60, 60, 400, type(uint128).max, type(uint128).max);
        vm.startPrank(alice);
        lpm.approve(bob, 1);
        lpm.approve(address(0), 1);
        vm.stopPrank();
        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), uint256(100), uint128(0), uint128(0), bytes(""));
        vm.expectRevert(IERC721Permit_v4.Unauthorized.selector);
        vm.prank(bob);
        _modify(actions, params);
    }

    // ── Deadlines & batching errors ───────────────────────────────────────────

    function test_edge_deadline_passed_reverts() public {
        uint256 deadline = block.timestamp + 10;
        vm.warp(block.timestamp + 11);
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(
            key, int24(-60), int24(60), uint256(100), type(uint128).max, type(uint128).max, address(this), bytes("")
        );
        vm.expectRevert(abi.encodeWithSelector(IPositionManager.DeadlinePassed.selector, deadline));
        _modifyDeadline(actions, params, deadline);
    }

    function test_edge_far_future_deadline_ok() public {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(
            key,
            int24(-60),
            int24(60),
            uint256(100),
            type(uint128).max,
            type(uint128).max,
            address(this),
            bytes("")
        );
        _modifyDeadline(actions, params, block.timestamp + 365 days);
        assertEq(lpm.positionLiquidity(1), 100);
    }

    function test_edge_input_length_mismatch_reverts() public {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.DECREASE_LIQUIDITY));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(
            key, int24(-60), int24(60), uint256(100), type(uint128).max, type(uint128).max, address(this), bytes("")
        );
        vm.expectRevert();
        _modify(actions, params);
    }

    // ── Slippage ──────────────────────────────────────────────────────────────

    function test_edge_mint_slippage_zero_max_reverts() public {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(key, int24(-60), int24(60), uint256(1000), uint128(0), uint128(0), address(this), bytes(""));
        vm.expectRevert();
        _modify(actions, params);
    }

    function test_edge_increase_slippage_zero_max_reverts() public {
        _mintThis(-60, 60, 100);
        bytes memory actions = abi.encodePacked(uint8(Actions.INCREASE_LIQUIDITY));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), uint256(500), uint128(0), uint128(0), bytes(""));
        vm.expectRevert();
        _modify(actions, params);
    }

    function test_edge_decrease_slippage_min_too_high_reverts() public {
        _mintThis(-60, 60, 2000);
        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), uint256(100), type(uint128).max, type(uint128).max, bytes(""));
        vm.expectRevert();
        _modify(actions, params);
    }

    function test_edge_burn_slippage_min_too_high_reverts() public {
        _mintThis(-60, 60, 100);
        bytes memory actions = abi.encodePacked(uint8(Actions.BURN_POSITION));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), type(uint128).max, type(uint128).max, bytes(""));
        vm.expectRevert();
        _modify(actions, params);
    }

    // ── Invalid token / ticks ─────────────────────────────────────────────────

    function test_edge_decrease_nonexistent_token_reverts() public {
        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(999), uint256(1), uint128(0), uint128(0), bytes(""));
        // onlyIfApproved runs before getPoolAndPositionInfo → Solmate ERC721 "NOT_MINTED"
        vm.expectRevert("NOT_MINTED");
        _modify(actions, params);
    }

    function test_edge_mint_misaligned_ticks_reverts() public {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory params = new bytes[](1);
        // tickSpacing 60 — tick 1 is invalid
        params[0] = abi.encode(
            key, int24(1), int24(60), uint256(100), type(uint128).max, type(uint128).max, address(this), bytes("")
        );
        vm.expectRevert();
        _modify(actions, params);
    }

    // ── Multicall: initialize + modify ────────────────────────────────────────

    function test_edge_multicall_initialize_then_mint() public {
        PoolManager freshManager = new PoolManager();
        PositionManager freshLpm = new PositionManager(freshManager);
        MockERC20 t0 = new MockERC20();
        MockERC20 t1 = new MockERC20();
        t0.mint(address(this), 20e18);
        t1.mint(address(this), 20e18);
        address a0 = address(t0);
        address a1 = address(t1);
        Currency c0 = a0 < a1 ? Currency.wrap(a0) : Currency.wrap(a1);
        Currency c1 = a0 < a1 ? Currency.wrap(a1) : Currency.wrap(a0);
        PoolKey memory k =
            PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: address(0)});

        (a0 < a1 ? t0 : t1).transfer(address(freshLpm), 5e18);
        (a0 < a1 ? t1 : t0).transfer(address(freshLpm), 5e18);
        (a0 < a1 ? t0 : t1).approve(address(freshLpm), type(uint256).max);
        (a0 < a1 ? t1 : t0).approve(address(freshLpm), type(uint256).max);

        bytes memory mintActions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory mintParams = new bytes[](1);
        mintParams[0] = abi.encode(
            k, int24(-60), int24(60), uint256(300), type(uint128).max, type(uint128).max, address(this), bytes("")
        );
        bytes memory unlockData = abi.encode(mintActions, mintParams);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(PositionManager.initializePool, (k, SQRT_PRICE_1_1));
        calls[1] = abi.encodeCall(PositionManager.modifyLiquidities, (unlockData, block.timestamp + 1000));

        freshLpm.multicall(calls);
        assertEq(freshLpm.positionLiquidity(1), 300);
    }

    // ── Composition with FROM_DELTAS + CLOSE (regression: no CurrencyNotSettled) ─

    function test_edge_mintFromDeltas_close_both_currencies_succeeds() public {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION_FROM_DELTAS), uint8(Actions.CLOSE_CURRENCY), uint8(Actions.CLOSE_CURRENCY)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            key, int24(-60), int24(60), uint256(600), type(uint128).max, type(uint128).max, address(this), bytes("")
        );
        params[1] = abi.encode(key.currency0);
        params[2] = abi.encode(key.currency1);
        _modify(actions, params);
        assertEq(lpm.positionLiquidity(1), 600);
    }

    function test_edge_decrease_then_close_currencies_no_residual() public {
        _mintThis(-60, 60, 1000);
        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.CLOSE_CURRENCY), uint8(Actions.CLOSE_CURRENCY)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(uint256(1), uint256(200), uint128(0), uint128(0), bytes(""));
        params[1] = abi.encode(key.currency0);
        params[2] = abi.encode(key.currency1);
        _modify(actions, params);
        assertEq(lpm.positionLiquidity(1), 800);
    }

    // ── Pool key storage / balance ────────────────────────────────────────────

    function test_edge_balanceOf_reflects_mints_and_burns() public {
        assertEq(lpm.balanceOf(address(this)), 0);
        _mintThis(-60, 60, 1);
        assertEq(lpm.balanceOf(address(this)), 1);
        _mintThis(-120, 120, 1);
        assertEq(lpm.balanceOf(address(this)), 2);
        bytes memory b = abi.encodePacked(uint8(Actions.BURN_POSITION));
        bytes[] memory p = new bytes[](1);
        p[0] = abi.encode(uint256(1), uint128(0), uint128(0), bytes(""));
        _modify(b, p);
        assertEq(lpm.balanceOf(address(this)), 1);
    }

    function test_edge_owner_mint_burn_cycle() public {
        _mintThis(-60, 60, 50);
        assertEq(lpm.ownerOf(1), address(this));
        bytes memory actions = abi.encodePacked(uint8(Actions.BURN_POSITION));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), uint128(0), uint128(0), bytes(""));
        _modify(actions, params);
        vm.expectRevert();
        lpm.ownerOf(1);
    }

    // ── Large-ish liquidity within funded PM ──────────────────────────────────

    function test_edge_large_liquidity_mint() public {
        _mintThis(-120, 120, 1_000_000);
        assertEq(lpm.positionLiquidity(1), 1_000_000);
    }

    // ── Alice full lifecycle as owner ─────────────────────────────────────────

    function test_edge_alice_mint_increase_decrease_burn() public {
        vm.startPrank(alice);
        bytes memory m = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory pm = new bytes[](1);
        pm[0] = abi.encode(
            key, int24(-60), int24(60), uint256(900), type(uint128).max, type(uint128).max, alice, bytes("")
        );
        lpm.modifyLiquidities(abi.encode(m, pm), block.timestamp + 1000);

        bytes memory i = abi.encodePacked(uint8(Actions.INCREASE_LIQUIDITY));
        bytes[] memory pi = new bytes[](1);
        pi[0] = abi.encode(uint256(1), uint256(100), type(uint128).max, type(uint128).max, bytes(""));
        lpm.modifyLiquidities(abi.encode(i, pi), block.timestamp + 1000);

        bytes memory d = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
        bytes[] memory pd = new bytes[](1);
        pd[0] = abi.encode(uint256(1), uint256(400), uint128(0), uint128(0), bytes(""));
        lpm.modifyLiquidities(abi.encode(d, pd), block.timestamp + 1000);

        bytes memory b = abi.encodePacked(uint8(Actions.BURN_POSITION));
        bytes[] memory pb = new bytes[](1);
        pb[0] = abi.encode(uint256(1), uint128(0), uint128(0), bytes(""));
        lpm.modifyLiquidities(abi.encode(b, pb), block.timestamp + 1000);
        vm.stopPrank();

        vm.expectRevert();
        lpm.ownerOf(1);
    }

    function test_edge_transfer_nft_new_owner_can_decrease() public {
        _mintThis(-60, 60, 600);
        lpm.transferFrom(address(this), bob, 1);
        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), uint256(100), uint128(0), uint128(0), bytes(""));
        vm.prank(bob);
        _modify(actions, params);
        assertEq(lpm.positionLiquidity(1), 500);
    }

    function test_edge_initializePool_second_call_returns_max_tick() public {
        // `key` is already initialized in setUp; use a different fee tier / tick spacing.
        PoolKey memory key500 =
            PoolKey({currency0: key.currency0, currency1: key.currency1, fee: 500, tickSpacing: 10, hooks: address(0)});
        int24 t1 = lpm.initializePool(key500, SQRT_PRICE_1_1);
        assertTrue(t1 != type(int24).max);
        int24 t2 = lpm.initializePool(key500, SQRT_PRICE_1_1);
        assertEq(t2, type(int24).max);
    }

    function test_edge_mintFromDeltas_settle_pair() public {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION_FROM_DELTAS), uint8(Actions.SETTLE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            key, int24(-60), int24(60), uint256(350), type(uint128).max, type(uint128).max, address(this), bytes("")
        );
        params[1] = abi.encode(key.currency0, key.currency1);
        _modify(actions, params);
        assertEq(lpm.positionLiquidity(1), 350);
    }

    function test_edge_two_increases_single_unlock() public {
        _mintThis(-60, 60, 200);
        bytes memory actions = abi.encodePacked(uint8(Actions.INCREASE_LIQUIDITY), uint8(Actions.INCREASE_LIQUIDITY));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(uint256(1), uint256(50), type(uint128).max, type(uint128).max, bytes(""));
        params[1] = abi.encode(uint256(1), uint256(75), type(uint128).max, type(uint128).max, bytes(""));
        _modify(actions, params);
        assertEq(lpm.positionLiquidity(1), 325);
    }

    function test_edge_decrease_all_liquidity_then_burn_same_unlock() public {
        _mintThis(-60, 60, 250);
        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.BURN_POSITION));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(uint256(1), uint256(250), uint128(0), uint128(0), bytes(""));
        params[1] = abi.encode(uint256(1), uint128(0), uint128(0), bytes(""));
        _modify(actions, params);
        vm.expectRevert("NOT_MINTED");
        lpm.ownerOf(1);
    }

    function test_edge_close_currency_when_no_open_delta() public {
        _mintThis(-60, 60, 100);
        bytes memory actions = abi.encodePacked(uint8(Actions.CLOSE_CURRENCY), uint8(Actions.CLOSE_CURRENCY));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(key.currency0);
        params[1] = abi.encode(key.currency1);
        _modify(actions, params);
        assertEq(lpm.positionLiquidity(1), 100);
    }

    function test_edge_three_mints_unique_positions() public {
        _mintThis(-60, 60, 10);
        _mintThis(-120, 120, 20);
        _mintThis(-180, 180, 30);
        assertEq(lpm.nextTokenId(), 4);
        assertEq(lpm.positionLiquidity(3), 30);
    }

    function test_edge_operator_increase_via_approvalForAll() public {
        _mint(alice, -60, 60, 500, type(uint128).max, type(uint128).max);
        vm.prank(alice);
        lpm.setApprovalForAll(bob, true);
        bytes memory actions = abi.encodePacked(uint8(Actions.INCREASE_LIQUIDITY));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(uint256(1), uint256(50), type(uint128).max, type(uint128).max, bytes(""));
        vm.prank(bob);
        _modify(actions, params);
        assertEq(lpm.positionLiquidity(1), 550);
    }
}
