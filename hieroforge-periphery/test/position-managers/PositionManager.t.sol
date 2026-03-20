// // SPDX-License-Identifier: Apache-2.0
// pragma solidity ^0.8.13;

// import {Test} from "forge-std/Test.sol";
// import {PoolManager} from "hieroforge-core/PoolManager.sol";
// import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
// import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
// import {Currency} from "hieroforge-core/types/Currency.sol";
// import {PositionInfo} from "../../src/types/PositionInfo.sol";
// import {MockERC20} from "../utils/MockERC20.sol";

// import {PositionManager} from "../../src/PositionManager.sol";
// import {IPositionManager} from "../../src/interfaces/IPositionManager.sol";
// import {IPoolInitializer_v4} from "../../src/interfaces/IPoolInitializer_v4.sol";
// import {IMulticall_v4} from "../../src/interfaces/IMulticall_v4.sol";
// import {IERC721Permit_v4} from "../../src/interfaces/IERC721Permit_v4.sol";
// import {Actions} from "../../src/libraries/Actions.sol";
// import {BaseActionsRouter} from "../../src/base/BaseActionsRouter.sol";
// import {htsSetup} from "hedera-forking/htsSetup.sol";

// /// @notice PositionManager tests. Run with --fork-url testnet --ffi.
// contract PositionManagerTest is Test {
//     IPoolManager public manager;
//     PositionManager public lpm;

//     uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

//     address public alice = makeAddr("alice");

//     PoolKey internal key;
//     MockERC20 internal token0;
//     MockERC20 internal token1;

//     function setUp() public {
//         htsSetup();
//         manager = new PoolManager();
//         lpm = new PositionManager(manager);

//         token0 = new MockERC20();
//         token1 = new MockERC20();
//         token0.mint(address(this), 10e18);
//         token1.mint(address(this), 10e18);

//         address a0 = address(token0);
//         address a1 = address(token1);
//         Currency c0 = a0 < a1 ? Currency.wrap(a0) : Currency.wrap(a1);
//         Currency c1 = a0 < a1 ? Currency.wrap(a1) : Currency.wrap(a0);

//         key = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: address(0)});
//         manager.initialize(key, SQRT_PRICE_1_1);

//         uint256 fundAmount = 5e18;
//         (a0 < a1 ? token0 : token1).transfer(address(lpm), fundAmount);
//         (a0 < a1 ? token1 : token0).transfer(address(lpm), fundAmount);
//     }

//     function _encodeMintUnlockData(
//         PoolKey memory poolKey,
//         int24 tickLower,
//         int24 tickUpper,
//         uint256 liquidity,
//         uint128 amount0Max,
//         uint128 amount1Max,
//         address owner,
//         bytes memory hookData
//     ) internal pure returns (bytes memory) {
//         bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION));
//         bytes[] memory params = new bytes[](1);
//         params[0] = abi.encode(poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, owner, hookData);
//         return abi.encode(actions, params);
//     }

//     /// @dev Encode unlock data for INCREASE_LIQUIDITY: tokenId, liquidity, amount0Max, amount1Max, hookData
//     function _encodeIncreaseLiquidityUnlockData(
//         uint256 tokenId,
//         uint256 liquidity,
//         uint128 amount0Max,
//         uint128 amount1Max,
//         bytes memory hookData
//     ) internal pure returns (bytes memory) {
//         bytes memory actions = abi.encodePacked(uint8(Actions.INCREASE_LIQUIDITY));
//         bytes[] memory params = new bytes[](1);
//         params[0] = abi.encode(tokenId, liquidity, amount0Max, amount1Max, hookData);
//         return abi.encode(actions, params);
//     }

//     /// @dev Encode unlock data for DECREASE_LIQUIDITY: tokenId, liquidity, amount0Min, amount1Min, hookData
//     function _encodeDecreaseLiquidityUnlockData(
//         uint256 tokenId,
//         uint256 liquidity,
//         uint128 amount0Min,
//         uint128 amount1Min,
//         bytes memory hookData
//     ) internal pure returns (bytes memory) {
//         bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
//         bytes[] memory params = new bytes[](1);
//         params[0] = abi.encode(tokenId, liquidity, amount0Min, amount1Min, hookData);
//         return abi.encode(actions, params);
//     }

//     function test_modifyLiquidities_reverts_deadlinePassed() public {
//         bytes memory unlockData =
//             _encodeMintUnlockData(key, -60, 60, 1e18, type(uint128).max, type(uint128).max, alice, "");
//         uint256 deadline = block.timestamp - 1;

//         vm.expectRevert(abi.encodeWithSelector(IPositionManager.DeadlinePassed.selector, deadline));
//         lpm.modifyLiquidities(unlockData, deadline);
//     }

//     function test_modifyLiquidities_mint_singlePosition() public {
//         bytes memory unlockData =
//             _encodeMintUnlockData(key, -60, 60, 1e18, type(uint128).max, type(uint128).max, alice, "");
//         uint256 deadline = block.timestamp + 1;

//         assertEq(lpm.nextTokenId(), 1, "nextTokenId before");

//         lpm.modifyLiquidities(unlockData, deadline);

//         assertEq(lpm.nextTokenId(), 2, "nextTokenId after");
//         assertEq(lpm.ownerOf(1), alice, "owner of token 1");
//         assertEq(lpm.balanceOf(alice), 1, "alice balance");
//     }

//     function test_modifyLiquidities_mint_toSelf() public {
//         bytes memory unlockData =
//             _encodeMintUnlockData(key, -60, 60, 1e18, type(uint128).max, type(uint128).max, address(this), "");
//         lpm.modifyLiquidities(unlockData, block.timestamp + 1);

//         assertEq(lpm.ownerOf(1), address(this));
//         assertEq(lpm.balanceOf(address(this)), 1);
//     }

//     function test_modifyLiquidities_reverts_mismatchedLengths() public {
//         bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION));
//         bytes[] memory params = new bytes[](0); // length mismatch
//         bytes memory unlockData = abi.encode(actions, params);

//         vm.expectRevert(BaseActionsRouter.InputLengthMismatch.selector);
//         lpm.modifyLiquidities(unlockData, block.timestamp + 1);
//     }

//     /// @notice Full modifyLiquidity path: mint position NFT (HTS at 0x167), add liquidity, settle. Uses shared pool from setUp.
//     /// @dev Pool uses MockERC20 (IERC20-compatible); position NFT uses hedera-forking HTS at 0x167.
//     function test_modifyLiquidity_withHTS() public {
//         bytes memory unlockData =
//             _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, alice, "");
//         uint256 deadline = block.timestamp + 1;

//         assertEq(lpm.nextTokenId(), 1, "nextTokenId before");
//         lpm.modifyLiquidities(unlockData, deadline);

//         assertEq(lpm.nextTokenId(), 2, "nextTokenId after");
//         assertEq(lpm.ownerOf(1), alice, "owner of token 1");
//         assertEq(lpm.balanceOf(alice), 1, "alice balance");

//         PositionInfo info = lpm.positionInfo(1);
//         assertEq(info.tickLower(), -120, "tickLower");
//         assertEq(info.tickUpper(), 120, "tickUpper");
//         (,,, int24 storedTickSpacing,) = lpm.poolKeys(info.poolId());
//         assertEq(storedTickSpacing, 60, "poolKeys stored");
//     }

//     /// @notice INCREASE_LIQUIDITY: mint a position, then increase liquidity on tokenId 1; caller must be owner or approved.
//     function test_modifyLiquidities_increaseLiquidity() public {
//         uint256 deadline = block.timestamp + 1;

//         // 1. Mint position 1 to alice (same range as setUp pool)
//         bytes memory mintData =
//             _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, alice, "");
//         lpm.modifyLiquidities(mintData, deadline);
//         assertEq(lpm.ownerOf(1), alice, "alice owns token 1");

//         // 2. Increase liquidity on position 1. Caller is this (test), so we must be owner or approved. Alice owns the NFT;
//         //    we call modifyLiquidities as this contract, so _executor is this. onlyIfApproved(this, 1) requires this to be
//         //    owner or approved for tokenId 1. We are not owner (alice is). So we need to either have alice call, or approve
//         //    this contract. Easiest: mint position to address(this) so we are owner, then increase.
//         mintData = _encodeMintUnlockData(key, -120, 120, 500, type(uint128).max, type(uint128).max, address(this), "");
//         lpm.modifyLiquidities(mintData, deadline);
//         assertEq(lpm.ownerOf(2), address(this), "this owns token 2");

//         // 3. Increase liquidity on position 2 (we are owner)
//         bytes memory increaseData = _encodeIncreaseLiquidityUnlockData(2, 300, type(uint128).max, type(uint128).max, "");
//         lpm.modifyLiquidities(increaseData, deadline);

//         // No revert means success; position 2 now has 500 + 300 = 800 liquidity in the pool
//         PositionInfo info2 = lpm.positionInfo(2);
//         assertEq(info2.tickLower(), -120, "tickLower");
//         assertEq(info2.tickUpper(), 120, "tickUpper");
//     }

//     /// @notice INCREASE_LIQUIDITY reverts when caller is not owner or approved for the token.
//     function test_modifyLiquidities_increaseLiquidity_reverts_whenNotApproved() public {
//         uint256 deadline = block.timestamp + 1;
//         bytes memory mintData =
//             _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, alice, "");
//         lpm.modifyLiquidities(mintData, deadline);
//         assertEq(lpm.ownerOf(1), alice);

//         // This contract is not owner of token 1 (alice is) and not approved → should revert
//         bytes memory increaseData = _encodeIncreaseLiquidityUnlockData(1, 100, type(uint128).max, type(uint128).max, "");
//         vm.expectRevert(abi.encodeWithSelector(IERC721Permit_v4.Unauthorized.selector));
//         lpm.modifyLiquidities(increaseData, deadline);
//     }

//     /// @notice DECREASE_LIQUIDITY: mint position, then decrease liquidity; caller receives tokens.
//     function test_modifyLiquidities_decreaseLiquidity() public {
//         uint256 deadline = block.timestamp + 1;

//         // 1. Mint position 1 to address(this)
//         bytes memory mintData =
//             _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, address(this), "");
//         lpm.modifyLiquidities(mintData, deadline);
//         assertEq(lpm.ownerOf(1), address(this));

//         uint256 bal0Before = (address(token0) < address(token1) ? token0 : token1).balanceOf(address(this));
//         uint256 bal1Before = (address(token0) < address(token1) ? token1 : token0).balanceOf(address(this));

//         // 2. Decrease liquidity on position 1 (remove 400 of 1000)
//         bytes memory decreaseData = _encodeDecreaseLiquidityUnlockData(1, 400, 0, 0, "");
//         lpm.modifyLiquidities(decreaseData, deadline);

//         uint256 bal0After = (address(token0) < address(token1) ? token0 : token1).balanceOf(address(this));
//         uint256 bal1After = (address(token0) < address(token1) ? token1 : token0).balanceOf(address(this));
//         assertGt(bal0After, bal0Before, "should receive token0");
//         assertGt(bal1After, bal1Before, "should receive token1");
//     }

//     /// @notice DECREASE_LIQUIDITY reverts when caller is not owner or approved for the token.
//     function test_modifyLiquidities_decreaseLiquidity_reverts_whenNotApproved() public {
//         uint256 deadline = block.timestamp + 1;
//         bytes memory mintData =
//             _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, alice, "");
//         lpm.modifyLiquidities(mintData, deadline);
//         assertEq(lpm.ownerOf(1), alice);

//         bytes memory decreaseData = _encodeDecreaseLiquidityUnlockData(1, 100, 0, 0, "");
//         vm.expectRevert(abi.encodeWithSelector(IERC721Permit_v4.Unauthorized.selector));
//         lpm.modifyLiquidities(decreaseData, deadline);
//     }

//     // ---------- initializePool ----------

//     /// @notice initializePool returns tick when pool was not initialized.
//     function test_initializePool_returnsTickWhenPoolNotInitialized() public {
//         MockERC20 token2 = new MockERC20();
//         MockERC20 token3 = new MockERC20();
//         token2.mint(address(this), 10e18);
//         token3.mint(address(this), 10e18);
//         address a2 = address(token2);
//         address a3 = address(token3);
//         PoolKey memory key2 = PoolKey({
//             currency0: a2 < a3 ? Currency.wrap(a2) : Currency.wrap(a3),
//             currency1: a2 < a3 ? Currency.wrap(a3) : Currency.wrap(a2),
//             fee: 3000,
//             tickSpacing: 60,
//             hooks: address(0)
//         });

//         int24 tick = IPoolInitializer_v4(address(lpm)).initializePool(key2, SQRT_PRICE_1_1);
//         assertTrue(tick != type(int24).max, "should return initial tick");

//         (bool initialized,,) = PoolManager(address(manager)).getPoolState(key2.toId());
//         assertTrue(initialized, "pool should be initialized");
//     }

//     /// @notice initializePool returns type(int24).max when pool already initialized (no revert).
//     function test_initializePool_returnsMaxWhenAlreadyInitialized() public {
//         int24 tick = IPoolInitializer_v4(address(lpm)).initializePool(key, SQRT_PRICE_1_1);
//         assertEq(tick, type(int24).max, "should return max when already initialized");
//     }

//     // ---------- multicall: initializePool + modifyLiquidities ----------

//     /// @notice multicall(initializePool, modifyLiquidities) initializes pool and mints position in one tx.
//     function test_multicall_initializePoolAndMintPosition() public {
//         MockERC20 token2 = new MockERC20();
//         MockERC20 token3 = new MockERC20();
//         token2.mint(address(this), 10e18);
//         token3.mint(address(this), 10e18);
//         address a2 = address(token2);
//         address a3 = address(token3);
//         PoolKey memory key2 = PoolKey({
//             currency0: a2 < a3 ? Currency.wrap(a2) : Currency.wrap(a3),
//             currency1: a2 < a3 ? Currency.wrap(a3) : Currency.wrap(a2),
//             fee: 3000,
//             tickSpacing: 60,
//             hooks: address(0)
//         });

//         uint256 fundAmount = 5e18;
//         (a2 < a3 ? token2 : token3).transfer(address(lpm), fundAmount);
//         (a2 < a3 ? token3 : token2).transfer(address(lpm), fundAmount);

//         bytes memory mintData =
//             _encodeMintUnlockData(key2, -60, 60, 1e18, type(uint128).max, type(uint128).max, alice, "");
//         uint256 deadline = block.timestamp + 1;

//         bytes[] memory calls = new bytes[](2);
//         calls[0] = abi.encodeWithSelector(IPoolInitializer_v4.initializePool.selector, key2, SQRT_PRICE_1_1);
//         calls[1] = abi.encodeWithSelector(IPositionManager.modifyLiquidities.selector, mintData, deadline);

//         assertEq(lpm.nextTokenId(), 1, "nextTokenId before");
//         bytes[] memory results = IMulticall_v4(address(lpm)).multicall(calls);
//         assertEq(results.length, 2, "two results");

//         (bool initialized,,) = PoolManager(address(manager)).getPoolState(key2.toId());
//         assertTrue(initialized, "pool should be initialized");
//         assertEq(lpm.nextTokenId(), 2, "nextTokenId after");
//         assertEq(lpm.ownerOf(1), alice, "owner of token 1");
//         assertEq(lpm.balanceOf(alice), 1, "alice balance");
//     }

//     // ==================== BURN_POSITION tests ====================

//     /// @dev Encode unlock data for BURN_POSITION: tokenId, amount0Min, amount1Min, hookData
//     function _encodeBurnUnlockData(uint256 tokenId, uint128 amount0Min, uint128 amount1Min, bytes memory hookData)
//         internal
//         pure
//         returns (bytes memory)
//     {
//         bytes memory actions = abi.encodePacked(uint8(Actions.BURN_POSITION));
//         bytes[] memory params = new bytes[](1);
//         params[0] = abi.encode(tokenId, amount0Min, amount1Min, hookData);
//         return abi.encode(actions, params);
//     }

//     /// @notice BURN_POSITION: mint, then burn position. NFT should be burned, positionInfo cleared.
//     function test_burn_position_basic() public {
//         uint256 deadline = block.timestamp + 1;

//         // 1. Mint position to address(this) with 1000 liquidity
//         bytes memory mintData =
//             _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, address(this), "");
//         lpm.modifyLiquidities(mintData, deadline);
//         assertEq(lpm.ownerOf(1), address(this), "minted to this");
//         assertEq(lpm.positionLiquidity(1), 1000, "tracked liquidity");

//         uint256 bal0Before = (address(token0) < address(token1) ? token0 : token1).balanceOf(address(this));
//         uint256 bal1Before = (address(token0) < address(token1) ? token1 : token0).balanceOf(address(this));

//         // 2. Burn the position (auto-decreases all liquidity)
//         bytes memory burnData = _encodeBurnUnlockData(1, 0, 0, "");
//         lpm.modifyLiquidities(burnData, deadline);

//         // 3. Verify: NFT burned, position cleared, tokens returned
//         vm.expectRevert("NOT_MINTED");
//         lpm.ownerOf(1);

//         assertEq(lpm.balanceOf(address(this)), 0, "balance should be 0 after burn");
//         assertEq(lpm.positionLiquidity(1), 0, "liquidity should be 0 after burn");

//         uint256 bal0After = (address(token0) < address(token1) ? token0 : token1).balanceOf(address(this));
//         uint256 bal1After = (address(token0) < address(token1) ? token1 : token0).balanceOf(address(this));
//         assertGt(bal0After, bal0Before, "should receive token0 back");
//         assertGt(bal1After, bal1Before, "should receive token1 back");
//     }

//     /// @notice BURN_POSITION after partial decrease: mint 1000, decrease 600, burn remaining 400
//     function test_burn_position_afterPartialDecrease() public {
//         uint256 deadline = block.timestamp + 1;

//         // Mint with 1000
//         bytes memory mintData =
//             _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, address(this), "");
//         lpm.modifyLiquidities(mintData, deadline);
//         assertEq(lpm.positionLiquidity(1), 1000);

//         // Decrease 600
//         bytes memory decreaseData = _encodeDecreaseLiquidityUnlockData(1, 600, 0, 0, "");
//         lpm.modifyLiquidities(decreaseData, deadline);
//         assertEq(lpm.positionLiquidity(1), 400, "liquidity after partial decrease");

//         // Burn the remaining 400
//         bytes memory burnData = _encodeBurnUnlockData(1, 0, 0, "");
//         lpm.modifyLiquidities(burnData, deadline);

//         // Verify NFT burned
//         vm.expectRevert("NOT_MINTED");
//         lpm.ownerOf(1);
//         assertEq(lpm.positionLiquidity(1), 0);
//     }

//     /// @notice BURN_POSITION reverts when caller is not owner or approved
//     function test_burn_position_reverts_whenNotApproved() public {
//         uint256 deadline = block.timestamp + 1;

//         // Mint to alice
//         bytes memory mintData =
//             _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, alice, "");
//         lpm.modifyLiquidities(mintData, deadline);
//         assertEq(lpm.ownerOf(1), alice);

//         // Try to burn from this contract (not approved) — should revert
//         bytes memory burnData = _encodeBurnUnlockData(1, 0, 0, "");
//         vm.expectRevert(abi.encodeWithSelector(IERC721Permit_v4.Unauthorized.selector));
//         lpm.modifyLiquidities(burnData, deadline);
//     }

//     /// @notice BURN_POSITION with approval: owner approves operator, operator burns
//     function test_burn_position_withApproval() public {
//         uint256 deadline = block.timestamp + 1;

//         // Mint to alice
//         bytes memory mintData =
//             _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, alice, "");
//         lpm.modifyLiquidities(mintData, deadline);

//         // Alice approves this contract
//         vm.prank(alice);
//         lpm.approve(address(this), 1);

//         // Now this contract can burn
//         bytes memory burnData = _encodeBurnUnlockData(1, 0, 0, "");
//         lpm.modifyLiquidities(burnData, deadline);

//         vm.expectRevert("NOT_MINTED");
//         lpm.ownerOf(1);
//     }

//     /// @notice Burn a position that already had all liquidity removed — should still burn NFT and collect fees
//     function test_burn_position_afterFullDecrease() public {
//         uint256 deadline = block.timestamp + 1;

//         // Mint with 1000
//         bytes memory mintData =
//             _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, address(this), "");
//         lpm.modifyLiquidities(mintData, deadline);

//         // Decrease all 1000
//         bytes memory decreaseData = _encodeDecreaseLiquidityUnlockData(1, 1000, 0, 0, "");
//         lpm.modifyLiquidities(decreaseData, deadline);
//         assertEq(lpm.positionLiquidity(1), 0, "liquidity is 0 after full decrease");

//         // Burn (0 liquidity remaining — just cleans up NFT + positionInfo)
//         bytes memory burnData = _encodeBurnUnlockData(1, 0, 0, "");
//         lpm.modifyLiquidities(burnData, deadline);

//         vm.expectRevert("NOT_MINTED");
//         lpm.ownerOf(1);
//     }

//     /// @notice Burn multiple positions sequentially
//     function test_burn_position_multiple() public {
//         uint256 deadline = block.timestamp + 1;

//         // Mint 2 positions
//         bytes memory m1 =
//             _encodeMintUnlockData(key, -120, 120, 500, type(uint128).max, type(uint128).max, address(this), "");
//         lpm.modifyLiquidities(m1, deadline);
//         bytes memory m2 =
//             _encodeMintUnlockData(key, -60, 60, 300, type(uint128).max, type(uint128).max, address(this), "");
//         lpm.modifyLiquidities(m2, deadline);

//         assertEq(lpm.ownerOf(1), address(this));
//         assertEq(lpm.ownerOf(2), address(this));
//         assertEq(lpm.balanceOf(address(this)), 2);

//         // Burn both
//         lpm.modifyLiquidities(_encodeBurnUnlockData(1, 0, 0, ""), deadline);
//         lpm.modifyLiquidities(_encodeBurnUnlockData(2, 0, 0, ""), deadline);

//         assertEq(lpm.balanceOf(address(this)), 0);
//     }

//     /// @notice positionLiquidity is accurately tracked through mint → increase → decrease → burn
//     function test_burn_position_liquidityTracking() public {
//         uint256 deadline = block.timestamp + 1;

//         bytes memory mintData =
//             _encodeMintUnlockData(key, -120, 120, 500, type(uint128).max, type(uint128).max, address(this), "");
//         lpm.modifyLiquidities(mintData, deadline);
//         assertEq(lpm.positionLiquidity(1), 500, "after mint");

//         bytes memory incData = _encodeIncreaseLiquidityUnlockData(1, 300, type(uint128).max, type(uint128).max, "");
//         lpm.modifyLiquidities(incData, deadline);
//         assertEq(lpm.positionLiquidity(1), 800, "after increase");

//         bytes memory decData = _encodeDecreaseLiquidityUnlockData(1, 200, 0, 0, "");
//         lpm.modifyLiquidities(decData, deadline);
//         assertEq(lpm.positionLiquidity(1), 600, "after decrease");

//         bytes memory burnData = _encodeBurnUnlockData(1, 0, 0, "");
//         lpm.modifyLiquidities(burnData, deadline);
//         assertEq(lpm.positionLiquidity(1), 0, "after burn");

//         vm.expectRevert("NOT_MINTED");
//         lpm.ownerOf(1);
//     }

//     // ==================== Slippage Validation tests ====================

//     /// @notice INCREASE_LIQUIDITY: slippage check should revert when amount0 exceeds max
//     function test_increase_slippage_reverts_amount0ExceedsMax() public {
//         uint256 deadline = block.timestamp + 1;

//         // Mint position
//         bytes memory mintData =
//             _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, address(this), "");
//         lpm.modifyLiquidities(mintData, deadline);

//         // Increase with very tight slippage (1 wei max for both tokens) — should revert
//         bytes memory increaseData = _encodeIncreaseLiquidityUnlockData(1, 500, 1, 1, "");
//         vm.expectRevert(); // SlippageCheckFailed
//         lpm.modifyLiquidities(increaseData, deadline);
//     }

//     /// @notice INCREASE_LIQUIDITY: slippage passes when maxes are generous
//     function test_increase_slippage_passes_withGeneroursLimits() public {
//         uint256 deadline = block.timestamp + 1;

//         bytes memory mintData =
//             _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, address(this), "");
//         lpm.modifyLiquidities(mintData, deadline);

//         // Increase with max uint128 — should pass
//         bytes memory increaseData = _encodeIncreaseLiquidityUnlockData(1, 500, type(uint128).max, type(uint128).max, "");
//         lpm.modifyLiquidities(increaseData, deadline);
//         assertEq(lpm.positionLiquidity(1), 1500, "liquidity increased");
//     }

//     /// @notice DECREASE_LIQUIDITY: slippage check should revert when amounts out are below minimum
//     function test_decrease_slippage_reverts_amountsBelowMin() public {
//         uint256 deadline = block.timestamp + 1;

//         // Mint with reasonable liquidity
//         bytes memory mintData =
//             _encodeMintUnlockData(key, -120, 120, 1e18, type(uint128).max, type(uint128).max, address(this), "");
//         lpm.modifyLiquidities(mintData, deadline);

//         // Decrease a small amount but demand unreasonably high minimums
//         bytes memory decreaseData = _encodeDecreaseLiquidityUnlockData(1, 100, type(uint128).max, type(uint128).max, "");
//         vm.expectRevert(); // SlippageCheckFailed
//         lpm.modifyLiquidities(decreaseData, deadline);
//     }

//     /// @notice DECREASE_LIQUIDITY: slippage passes when minimums are 0
//     function test_decrease_slippage_passes_withZeroMinimums() public {
//         uint256 deadline = block.timestamp + 1;

//         bytes memory mintData =
//             _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, address(this), "");
//         lpm.modifyLiquidities(mintData, deadline);

//         bytes memory decreaseData = _encodeDecreaseLiquidityUnlockData(1, 500, 0, 0, "");
//         lpm.modifyLiquidities(decreaseData, deadline);
//         assertEq(lpm.positionLiquidity(1), 500, "liquidity decreased");
//     }

//     /// @notice MINT_POSITION: slippage check should revert when amounts exceed max
//     function test_mint_slippage_reverts_amountsExceedMax() public {
//         uint256 deadline = block.timestamp + 1;

//         // Mint with very tight slippage — 1 wei max
//         bytes memory mintData = _encodeMintUnlockData(key, -120, 120, 1e18, 1, 1, address(this), "");
//         vm.expectRevert(); // SlippageCheckFailed
//         lpm.modifyLiquidities(mintData, deadline);
//     }

//     /// @notice BURN_POSITION: slippage check should revert when returned amounts are below min
//     function test_burn_slippage_reverts_amountsBelowMin() public {
//         uint256 deadline = block.timestamp + 1;

//         // Mint a small position
//         bytes memory mintData =
//             _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, address(this), "");
//         lpm.modifyLiquidities(mintData, deadline);

//         // Burn with unreasonably high minimums
//         bytes memory burnData = _encodeBurnUnlockData(1, type(uint128).max, type(uint128).max, "");
//         vm.expectRevert(); // SlippageCheckFailed
//         lpm.modifyLiquidities(burnData, deadline);
//     }

//     /// @notice BURN_POSITION: slippage passes with 0 minimums
//     function test_burn_slippage_passes_withZeroMinimums() public {
//         uint256 deadline = block.timestamp + 1;

//         bytes memory mintData =
//             _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, address(this), "");
//         lpm.modifyLiquidities(mintData, deadline);

//         bytes memory burnData = _encodeBurnUnlockData(1, 0, 0, "");
//         lpm.modifyLiquidities(burnData, deadline);

//         vm.expectRevert("NOT_MINTED");
//         lpm.ownerOf(1);
//     }

//     /// @notice Increase with 0 liquidity should collect fees without slippage revert
//     function test_increase_zeroLiquidity_collectFees_noSlippageRevert() public {
//         uint256 deadline = block.timestamp + 1;

//         bytes memory mintData =
//             _encodeMintUnlockData(key, -120, 120, 1000, type(uint128).max, type(uint128).max, address(this), "");
//         lpm.modifyLiquidities(mintData, deadline);

//         // Increase with 0 liquidity and 0 maxes — should not revert (no principal change)
//         bytes memory increaseData = _encodeIncreaseLiquidityUnlockData(1, 0, 0, 0, "");
//         lpm.modifyLiquidities(increaseData, deadline);
//         assertEq(lpm.positionLiquidity(1), 1000, "liquidity unchanged");
//     }
// }
