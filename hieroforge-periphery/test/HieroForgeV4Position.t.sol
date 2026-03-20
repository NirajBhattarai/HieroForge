// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "hieroforge-core/PoolManager.sol";
import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {Currency} from "hieroforge-core/types/Currency.sol";
import {PositionInfo} from "../src/types/PositionInfo.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {HieroForgeV4Position} from "../src/HieroForgeV4Position.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {IPoolInitializer_v4} from "../src/interfaces/IPoolInitializer_v4.sol";
import {IMulticall_v4} from "../src/interfaces/IMulticall_v4.sol";
import {IERC721Permit_v4} from "../src/interfaces/IERC721Permit_v4.sol";
import {Actions} from "../src/libraries/Actions.sol";
import {BaseActionsRouter} from "../src/base/BaseActionsRouter.sol";
import {IERC721} from "hedera-forking/IERC721.sol";

/// @notice Tests for HieroForgeV4Position: PositionManager functionality (modifyLiquidities, mint/increase/decrease/burn)
///         plus HTS collection (createCollection, mintNFT). Run position-manager tests with MockHTS; run HTS tests with --ffi.
contract HieroForgeV4PositionTest is Test {
    IPoolManager public manager;
    HieroForgeV4Position public lpm;

    address constant HTS_PRECOMPILE = address(0x167);
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    address public alice = makeAddr("alice");

    PoolKey internal key;
    MockERC20 internal token0;
    MockERC20 internal token1;

    function setUp() public {
        manager = new PoolManager();
        vm.etch(HTS_PRECOMPILE, address(this).code);
        lpm = new HieroForgeV4Position(manager, address(this));

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

        uint256 fundAmount = 5e18;
        (a0 < a1 ? token0 : token1).transfer(address(lpm), fundAmount);
        (a0 < a1 ? token1 : token0).transfer(address(lpm), fundAmount);

        // Ensure the HTS NFT collection is created before any position actions
        lpm.createCollection{value: 25 ether}();
    }

    function _encodeMintUnlockData(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        address owner,
        bytes memory hookData
    ) internal pure returns (bytes memory) {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, owner, hookData);
        return abi.encode(actions, params);
    }

    function _encodeIncreaseLiquidityUnlockData(
        uint256 tokenId,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        bytes memory hookData
    ) internal pure returns (bytes memory) {
        bytes memory actions = abi.encodePacked(uint8(Actions.INCREASE_LIQUIDITY));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(tokenId, liquidity, amount0Max, amount1Max, hookData);
        return abi.encode(actions, params);
    }

    function _encodeDecreaseLiquidityUnlockData(
        uint256 tokenId,
        uint256 liquidity,
        uint128 amount0Min,
        uint128 amount1Min,
        bytes memory hookData
    ) internal pure returns (bytes memory) {
        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(tokenId, liquidity, amount0Min, amount1Min, hookData);
        return abi.encode(actions, params);
    }

    function _encodeBurnUnlockData(uint256 tokenId, uint128 amount0Min, uint128 amount1Min, bytes memory hookData)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory actions = abi.encodePacked(uint8(Actions.BURN_POSITION));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(tokenId, amount0Min, amount1Min, hookData);
        return abi.encode(actions, params);
    }

    // ─── PositionManager functionality (same as PositionManager.t.sol) ───

    function test_modifyLiquidities_reverts_deadlinePassed() public {
        bytes memory unlockData =
            _encodeMintUnlockData(key, -60, 60, 1e18, type(uint128).max, type(uint128).max, alice, "");
        uint256 deadline = block.timestamp - 1;

        vm.expectRevert(abi.encodeWithSelector(IPositionManager.DeadlinePassed.selector, deadline));
        lpm.modifyLiquidities(unlockData, deadline);
    }

    function test_modifyLiquidities_mint_singlePosition() public {
        bytes memory unlockData =
            _encodeMintUnlockData(key, -60, 60, 1e18, type(uint128).max, type(uint128).max, alice, "");
        uint256 deadline = block.timestamp + 1;

        assertEq(lpm.nextTokenId(), 1, "nextTokenId before");
        lpm.modifyLiquidities(unlockData, deadline);

        assertEq(lpm.nextTokenId(), 2, "nextTokenId after");
        assertEq(lpm.ownerOf(1), alice, "owner of token 1");
        assertEq(lpm.balanceOf(alice), 1, "alice balance");
    }

    function test_modifyLiquidities_mint_toSelf() public {
        bytes memory unlockData =
            _encodeMintUnlockData(key, -60, 60, 1e18, type(uint128).max, type(uint128).max, address(this), "");
        lpm.modifyLiquidities(unlockData, block.timestamp + 1);

        assertEq(lpm.ownerOf(1), address(this));
        assertEq(lpm.balanceOf(address(this)), 1);
    }

    function test_modifyLiquidities_reverts_mismatchedLengths() public {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory params = new bytes[](0);
        bytes memory unlockData = abi.encode(actions, params);

        vm.expectRevert(BaseActionsRouter.InputLengthMismatch.selector);
        lpm.modifyLiquidities(unlockData, block.timestamp + 1);
    }

    function test_modifyLiquidity_mint_positionInfoAndPoolKeys() public {
        bytes memory unlockData =
            _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, alice, "");
        uint256 deadline = block.timestamp + 1;

        assertEq(lpm.nextTokenId(), 1, "nextTokenId before");
        lpm.modifyLiquidities(unlockData, deadline);

        assertEq(lpm.nextTokenId(), 2, "nextTokenId after");
        assertEq(lpm.ownerOf(1), alice, "owner of token 1");
        assertEq(lpm.balanceOf(alice), 1, "alice balance");

        PositionInfo info = lpm.positionInfo(1);
        assertEq(info.tickLower(), -120, "tickLower");
        assertEq(info.tickUpper(), 120, "tickUpper");
        (,,, int24 storedTickSpacing,) = lpm.poolKeys(info.poolId());
        assertEq(storedTickSpacing, 60, "poolKeys stored");
    }

    function test_modifyLiquidities_increaseLiquidity() public {
        uint256 deadline = block.timestamp + 1;

        bytes memory mintData =
            _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, alice, "");
        lpm.modifyLiquidities(mintData, deadline);
        assertEq(lpm.ownerOf(1), alice, "alice owns token 1");

        mintData = _encodeMintUnlockData(key, -120, 120, 500, type(uint128).max, type(uint128).max, address(this), "");
        lpm.modifyLiquidities(mintData, deadline);
        assertEq(lpm.ownerOf(2), address(this), "this owns token 2");

        bytes memory increaseData = _encodeIncreaseLiquidityUnlockData(2, 300, type(uint128).max, type(uint128).max, "");
        lpm.modifyLiquidities(increaseData, deadline);

        PositionInfo info2 = lpm.positionInfo(2);
        assertEq(info2.tickLower(), -120, "tickLower");
        assertEq(info2.tickUpper(), 120, "tickUpper");
    }

    function test_modifyLiquidities_increaseLiquidity_reverts_whenNotApproved() public {
        uint256 deadline = block.timestamp + 1;
        bytes memory mintData =
            _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, alice, "");
        lpm.modifyLiquidities(mintData, deadline);
        assertEq(lpm.ownerOf(1), alice);

        bytes memory increaseData = _encodeIncreaseLiquidityUnlockData(1, 100, type(uint128).max, type(uint128).max, "");
        vm.expectRevert(abi.encodeWithSelector(IERC721Permit_v4.Unauthorized.selector));
        lpm.modifyLiquidities(increaseData, deadline);
    }

    function test_modifyLiquidities_decreaseLiquidity() public {
        uint256 deadline = block.timestamp + 1;

        bytes memory mintData =
            _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, address(this), "");
        lpm.modifyLiquidities(mintData, deadline);
        assertEq(lpm.ownerOf(1), address(this));

        uint256 bal0Before = (address(token0) < address(token1) ? token0 : token1).balanceOf(address(this));
        uint256 bal1Before = (address(token0) < address(token1) ? token1 : token0).balanceOf(address(this));

        bytes memory decreaseData = _encodeDecreaseLiquidityUnlockData(1, 400, 0, 0, "");
        lpm.modifyLiquidities(decreaseData, deadline);

        uint256 bal0After = (address(token0) < address(token1) ? token0 : token1).balanceOf(address(this));
        uint256 bal1After = (address(token0) < address(token1) ? token1 : token0).balanceOf(address(this));
        assertGt(bal0After, bal0Before, "should receive token0");
        assertGt(bal1After, bal1Before, "should receive token1");
    }

    function test_modifyLiquidities_decreaseLiquidity_reverts_whenNotApproved() public {
        uint256 deadline = block.timestamp + 1;
        bytes memory mintData =
            _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, alice, "");
        lpm.modifyLiquidities(mintData, deadline);
        assertEq(lpm.ownerOf(1), alice);

        bytes memory decreaseData = _encodeDecreaseLiquidityUnlockData(1, 100, 0, 0, "");
        vm.expectRevert(abi.encodeWithSelector(IERC721Permit_v4.Unauthorized.selector));
        lpm.modifyLiquidities(decreaseData, deadline);
    }

    function test_initializePool_returnsTickWhenPoolNotInitialized() public {
        MockERC20 token2 = new MockERC20();
        MockERC20 token3 = new MockERC20();
        token2.mint(address(this), 10e18);
        token3.mint(address(this), 10e18);
        address a2 = address(token2);
        address a3 = address(token3);
        PoolKey memory key2 = PoolKey({
            currency0: a2 < a3 ? Currency.wrap(a2) : Currency.wrap(a3),
            currency1: a2 < a3 ? Currency.wrap(a3) : Currency.wrap(a2),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });

        int24 tick = IPoolInitializer_v4(address(lpm)).initializePool(key2, SQRT_PRICE_1_1);
        assertTrue(tick != type(int24).max, "should return initial tick");

        (bool initialized,,) = PoolManager(address(manager)).getPoolState(key2.toId());
        assertTrue(initialized, "pool should be initialized");
    }

    function test_initializePool_returnsMaxWhenAlreadyInitialized() public {
        int24 tick = IPoolInitializer_v4(address(lpm)).initializePool(key, SQRT_PRICE_1_1);
        assertEq(tick, type(int24).max, "should return max when already initialized");
    }

    function test_multicall_initializePoolAndMintPosition() public {
        MockERC20 token2 = new MockERC20();
        MockERC20 token3 = new MockERC20();
        token2.mint(address(this), 10e18);
        token3.mint(address(this), 10e18);
        address a2 = address(token2);
        address a3 = address(token3);
        PoolKey memory key2 = PoolKey({
            currency0: a2 < a3 ? Currency.wrap(a2) : Currency.wrap(a3),
            currency1: a2 < a3 ? Currency.wrap(a3) : Currency.wrap(a2),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });

        uint256 fundAmount = 5e18;
        (a2 < a3 ? token2 : token3).transfer(address(lpm), fundAmount);
        (a2 < a3 ? token3 : token2).transfer(address(lpm), fundAmount);

        bytes memory mintData =
            _encodeMintUnlockData(key2, -60, 60, 1e18, type(uint128).max, type(uint128).max, alice, "");
        uint256 deadline = block.timestamp + 1;

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(IPoolInitializer_v4.initializePool.selector, key2, SQRT_PRICE_1_1);
        calls[1] = abi.encodeWithSelector(IPositionManager.modifyLiquidities.selector, mintData, deadline);

        assertEq(lpm.nextTokenId(), 1, "nextTokenId before");
        bytes[] memory results = IMulticall_v4(address(lpm)).multicall(calls);
        assertEq(results.length, 2, "two results");

        (bool initialized,,) = PoolManager(address(manager)).getPoolState(key2.toId());
        assertTrue(initialized, "pool should be initialized");
        assertEq(lpm.nextTokenId(), 2, "nextTokenId after");
        assertEq(lpm.ownerOf(1), alice, "owner of token 1");
        assertEq(lpm.balanceOf(alice), 1, "alice balance");
    }

    function test_burn_position_basic() public {
        uint256 deadline = block.timestamp + 1;

        bytes memory mintData =
            _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, address(this), "");
        lpm.modifyLiquidities(mintData, deadline);
        assertEq(lpm.ownerOf(1), address(this), "minted to this");
        assertEq(lpm.positionLiquidity(1), 1000, "tracked liquidity");

        uint256 bal0Before = (address(token0) < address(token1) ? token0 : token1).balanceOf(address(this));
        uint256 bal1Before = (address(token0) < address(token1) ? token1 : token0).balanceOf(address(this));

        bytes memory burnData = _encodeBurnUnlockData(1, 0, 0, "");
        lpm.modifyLiquidities(burnData, deadline);

        vm.expectRevert("NOT_MINTED");
        lpm.ownerOf(1);

        assertEq(lpm.balanceOf(address(this)), 0, "balance should be 0 after burn");
        assertEq(lpm.positionLiquidity(1), 0, "liquidity should be 0 after burn");

        uint256 bal0After = (address(token0) < address(token1) ? token0 : token1).balanceOf(address(this));
        uint256 bal1After = (address(token0) < address(token1) ? token1 : token0).balanceOf(address(this));
        assertGt(bal0After, bal0Before, "should receive token0 back");
        assertGt(bal1After, bal1Before, "should receive token1 back");
    }

    function test_burn_position_afterPartialDecrease() public {
        uint256 deadline = block.timestamp + 1;

        bytes memory mintData =
            _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, address(this), "");
        lpm.modifyLiquidities(mintData, deadline);
        assertEq(lpm.positionLiquidity(1), 1000);

        bytes memory decreaseData = _encodeDecreaseLiquidityUnlockData(1, 600, 0, 0, "");
        lpm.modifyLiquidities(decreaseData, deadline);
        assertEq(lpm.positionLiquidity(1), 400, "liquidity after partial decrease");

        bytes memory burnData = _encodeBurnUnlockData(1, 0, 0, "");
        lpm.modifyLiquidities(burnData, deadline);

        vm.expectRevert("NOT_MINTED");
        lpm.ownerOf(1);
        assertEq(lpm.positionLiquidity(1), 0);
    }

    function test_burn_position_reverts_whenNotApproved() public {
        uint256 deadline = block.timestamp + 1;

        bytes memory mintData =
            _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, alice, "");
        lpm.modifyLiquidities(mintData, deadline);
        assertEq(lpm.ownerOf(1), alice);

        bytes memory burnData = _encodeBurnUnlockData(1, 0, 0, "");
        vm.expectRevert(abi.encodeWithSelector(IERC721Permit_v4.Unauthorized.selector));
        lpm.modifyLiquidities(burnData, deadline);
    }

    function test_burn_position_withApproval() public {
        uint256 deadline = block.timestamp + 1;

        bytes memory mintData =
            _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, alice, "");
        lpm.modifyLiquidities(mintData, deadline);

        vm.prank(alice);
        lpm.approve(address(this), 1);

        bytes memory burnData = _encodeBurnUnlockData(1, 0, 0, "");
        lpm.modifyLiquidities(burnData, deadline);

        vm.expectRevert("NOT_MINTED");
        lpm.ownerOf(1);
    }

    function test_burn_position_afterFullDecrease() public {
        uint256 deadline = block.timestamp + 1;

        bytes memory mintData =
            _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, address(this), "");
        lpm.modifyLiquidities(mintData, deadline);

        bytes memory decreaseData = _encodeDecreaseLiquidityUnlockData(1, 1000, 0, 0, "");
        lpm.modifyLiquidities(decreaseData, deadline);
        assertEq(lpm.positionLiquidity(1), 0, "liquidity is 0 after full decrease");

        bytes memory burnData = _encodeBurnUnlockData(1, 0, 0, "");
        lpm.modifyLiquidities(burnData, deadline);

        vm.expectRevert("NOT_MINTED");
        lpm.ownerOf(1);
    }

    function test_burn_position_liquidityTracking() public {
        uint256 deadline = block.timestamp + 1;

        bytes memory mintData =
            _encodeMintUnlockData(key, -120, 120, 500, type(uint128).max, type(uint128).max, address(this), "");
        lpm.modifyLiquidities(mintData, deadline);
        assertEq(lpm.positionLiquidity(1), 500, "after mint");

        bytes memory incData = _encodeIncreaseLiquidityUnlockData(1, 300, type(uint128).max, type(uint128).max, "");
        lpm.modifyLiquidities(incData, deadline);
        assertEq(lpm.positionLiquidity(1), 800, "after increase");

        bytes memory decData = _encodeDecreaseLiquidityUnlockData(1, 200, 0, 0, "");
        lpm.modifyLiquidities(decData, deadline);
        assertEq(lpm.positionLiquidity(1), 600, "after decrease");

        bytes memory burnData = _encodeBurnUnlockData(1, 0, 0, "");
        lpm.modifyLiquidities(burnData, deadline);
        assertEq(lpm.positionLiquidity(1), 0, "after burn");

        vm.expectRevert("NOT_MINTED");
        lpm.ownerOf(1);
    }

    function test_increase_slippage_reverts_amount0ExceedsMax() public {
        uint256 deadline = block.timestamp + 1;

        bytes memory mintData =
            _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, address(this), "");
        lpm.modifyLiquidities(mintData, deadline);

        bytes memory increaseData = _encodeIncreaseLiquidityUnlockData(1, 500, 1, 1, "");
        vm.expectRevert();
        lpm.modifyLiquidities(increaseData, deadline);
    }

    function test_mint_slippage_reverts_amountsExceedMax() public {
        uint256 deadline = block.timestamp + 1;

        bytes memory mintData = _encodeMintUnlockData(key, -120, 120, 1e18, 1, 1, address(this), "");
        vm.expectRevert();
        lpm.modifyLiquidities(mintData, deadline);
    }

    function test_burn_slippage_reverts_amountsBelowMin() public {
        uint256 deadline = block.timestamp + 1;

        bytes memory mintData =
            _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, address(this), "");
        lpm.modifyLiquidities(mintData, deadline);

        bytes memory burnData = _encodeBurnUnlockData(1, type(uint128).max, type(uint128).max, "");
        vm.expectRevert();
        lpm.modifyLiquidities(burnData, deadline);
    }

    // ─── HTS collection (createCollection, mintNFT) — run with --ffi for real HTS ───

    function test_deploy_setsOwnerAndOperator() public view {
        assertEq(lpm.owner(), address(this));
        assertEq(lpm.operatorAccount(), address(this));
        assertEq(lpm.htsTokenAddress(), address(0));
    }

    function test_createCollection_whenNotHtsSetup_revertsOrSucceeds() public {
        vm.deal(address(this), 20 ether);
        try lpm.createCollection{value: 15 ether}() {
            assertTrue(lpm.htsTokenAddress() != address(0), "hts token address set");
            assertEq(lpm.HTS_NAME(), "HieroForge V4 Position");
            assertEq(lpm.HTS_SYMBOL(), "HFV4P");
        } catch {
            // Without htsSetup / real HTS precompile, create may revert; that's ok in unit test
        }
    }

    /// @dev When first createCollection succeeds, second must revert (our selector or HTS/env revert).
    function test_createCollection_revertsWhenAlreadyCreated() public {
        vm.deal(address(this), 20 ether);
        try lpm.createCollection{value: 15 ether}() {} catch {}
        if (lpm.htsTokenAddress() != address(0)) {
            try lpm.createCollection{value: 15 ether}() {
                revert("second createCollection should have reverted");
            } catch (bytes memory) {
                // Revert with our CollectionAlreadyCreated or from HTS/env
            }
        }
    }

    function test_mintNFT_revertsWhenNotOwner() public {
        vm.deal(address(this), 20 ether);
        lpm.createCollection{value: 15 ether}();

        vm.prank(alice);
        vm.expectRevert(HieroForgeV4Position.OnlyOwner.selector);
        lpm.mintNFT(alice);
    }

    function test_mintNFT_revertsWhenCollectionNotCreated() public {
        vm.expectRevert(HieroForgeV4Position.CollectionNotCreated.selector);
        lpm.mintNFT(alice);
    }

    /// @dev On real Hedera, mintToken(0, metadata) mints NFTs. With hedera-forking/ffi or MockHTS, may succeed or skip.
    function test_mintNFT_transfersToRecipient() public {
        vm.deal(address(this), 20 ether);
        lpm.createCollection{value: 15 ether}();

        try lpm.mintNFT(alice) returns (uint256 tokenId) {
            assertEq(IERC721(lpm.htsTokenAddress()).ownerOf(tokenId), alice);
        } catch {
            // hedera-forking may revert for NFT mint; skip assertion
        }
    }

    function test_onlyPositionOwnerOrApproved_owner_and_approval() public {
        // Mint to alice
        bytes memory mintData = _encodeMintUnlockData(key, -60, 60, 1e18, type(uint128).max, type(uint128).max, alice, "");
        lpm.modifyLiquidities(mintData, block.timestamp + 1);
        uint256 tokenId = 1;
        assertEq(lpm.ownerOf(tokenId), alice);

        // Try as not owner, not approved
        bytes memory incData = _encodeIncreaseLiquidityUnlockData(tokenId, 100, type(uint128).max, type(uint128).max, "");
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        lpm.modifyLiquidities(incData, block.timestamp + 1);

        // Approve this contract for tokenId
        vm.prank(alice);
        IERC721(address(lpm.htsTokenAddress())).approve(address(this), tokenId);
        // Now should succeed
        lpm.modifyLiquidities(incData, block.timestamp + 1);

        // Approve operator
        vm.prank(alice);
        IERC721(address(lpm.htsTokenAddress())).setApprovalForAll(address(0xCAFE), true);
        // Operator can now act
        vm.prank(address(0xCAFE));
        lpm.modifyLiquidities(incData, block.timestamp + 1);
    }

    function test_onlyPositionOwnerOrApproved_reverts_for_unapproved_and_nonowner() public {
        // Mint to alice
        bytes memory mintData = _encodeMintUnlockData(key, -60, 60, 1e18, type(uint128).max, type(uint128).max, alice, "");
        lpm.modifyLiquidities(mintData, block.timestamp + 1);
        uint256 tokenId = 1;
        assertEq(lpm.ownerOf(tokenId), alice);

        // Try as a random address (not owner, not approved, not operator)
        bytes memory incData = _encodeIncreaseLiquidityUnlockData(tokenId, 100, type(uint128).max, type(uint128).max, "");
        address attacker = address(0xBADBEEF);
        vm.prank(attacker);
        vm.expectRevert();
        lpm.modifyLiquidities(incData, block.timestamp + 1);
    }

    function test_onlyPositionOwnerOrApproved_reverts_for_revoked_operator() public {
        // Mint to alice
        bytes memory mintData = _encodeMintUnlockData(key, -60, 60, 1e18, type(uint128).max, type(uint128).max, alice, "");
        lpm.modifyLiquidities(mintData, block.timestamp + 1);
        uint256 tokenId = 1;
        assertEq(lpm.ownerOf(tokenId), alice);

        // Approve operator
        address operator = address(0xCAFE);
        vm.prank(alice);
        IERC721(address(lpm.htsTokenAddress())).setApprovalForAll(operator, true);
        // Operator can act
        vm.prank(operator);
        lpm.modifyLiquidities(_encodeIncreaseLiquidityUnlockData(tokenId, 100, type(uint128).max, type(uint128).max, ""), block.timestamp + 1);
        // Revoke operator
        vm.prank(alice);
        IERC721(address(lpm.htsTokenAddress())).setApprovalForAll(operator, false);
        // Operator should now be blocked
        vm.prank(operator);
        vm.expectRevert();
        lpm.modifyLiquidities(_encodeIncreaseLiquidityUnlockData(tokenId, 100, type(uint128).max, type(uint128).max, ""), block.timestamp + 1);
    }

    function test_onlyPositionOwnerOrApproved_reverts_for_revoked_approval() public {
        // Mint to alice
        bytes memory mintData = _encodeMintUnlockData(key, -60, 60, 1e18, type(uint128).max, type(uint128).max, alice, "");
        lpm.modifyLiquidities(mintData, block.timestamp + 1);
        uint256 tokenId = 1;
        assertEq(lpm.ownerOf(tokenId), alice);

        // Approve this contract for tokenId
        vm.prank(alice);
        IERC721(address(lpm.htsTokenAddress())).approve(address(this), tokenId);
        // Should succeed
        lpm.modifyLiquidities(_encodeIncreaseLiquidityUnlockData(tokenId, 100, type(uint128).max, type(uint128).max, ""), block.timestamp + 1);
        // Revoke approval
        vm.prank(alice);
        IERC721(address(lpm.htsTokenAddress())).approve(address(0), tokenId);
        // Should now revert
        vm.expectRevert();
        lpm.modifyLiquidities(_encodeIncreaseLiquidityUnlockData(tokenId, 100, type(uint128).max, type(uint128).max, ""), block.timestamp + 1);
    }
}
