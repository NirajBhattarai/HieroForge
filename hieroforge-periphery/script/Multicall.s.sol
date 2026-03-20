// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PositionManager} from "../src/PositionManager.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {IMulticall_v4} from "../src/interfaces/IMulticall_v4.sol";
import {Hsc} from "hedera-forking/Hsc.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {Currency} from "hieroforge-core/types/Currency.sol";
import {Actions} from "../src/libraries/Actions.sol";
import {TickMath} from "hieroforge-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "hieroforge-core/libraries/SqrtPriceMath.sol";

/// @dev Minimal interface for HTS/ERC20 approve (token proxy implements this)
interface IERC20Approve {
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @notice Helper: compute amount0 and amount1 (raw token units) for a position given tick range and liquidity.
/// @param tickLower Lower tick of the position (must be aligned to pool tickSpacing).
/// @param tickUpper Upper tick of the position (must be aligned to pool tickSpacing).
/// @param liquidity Liquidity L (same units as pool).
/// @return amount0 Maximum amount of currency0 required (round up).
/// @return amount1 Maximum amount of currency1 required (round up).
function getAmountsForLiquidity(int24 tickLower, int24 tickUpper, uint128 liquidity)
    pure
    returns (uint256 amount0, uint256 amount1)
{
    uint160 sqrtPriceLower = TickMath.getSqrtPriceAtTickPublic(tickLower);
    uint160 sqrtPriceUpper = TickMath.getSqrtPriceAtTickPublic(tickUpper);
    amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceLower, sqrtPriceUpper, liquidity, true);
    amount1 = SqrtPriceMath.getAmount1Delta(sqrtPriceLower, sqrtPriceUpper, liquidity, true);
}

/// @notice Multicall script: initialize pool and/or mint position (add liquidity) via PositionManager.
/// Uses HTS fungible tokens (4 decimals): amounts are in raw units (1 token = 1e4). Script approves
/// both tokens for the PositionManager then mints position from deltas and settles in one multicall.
/// Usage:
///   export PRIVATE_KEY=0x... POSITION_MANAGER_ADDRESS=0x... CURRENCY0_ADDRESS=0x... CURRENCY1_ADDRESS=0x...
///   forge script script/Multicall.s.sol:MulticallScript --rpc-url testnet --broadcast --private-key $PRIVATE_KEY
contract MulticallScript is Script {
    address internal constant HTS_PRECOMPILE = address(0x167);

    function run() external {
        Hsc.htsSetup();
        address c0 = vm.envAddress("CURRENCY0_ADDRESS");
        address c1 = vm.envAddress("CURRENCY1_ADDRESS");

        (address currency0, address currency1) = c0 < c1 ? (c0, c1) : (c1, c0);

        int24 tickSpacing = 60;
        uint24 fee = 3000;

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: address(0)
        });

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(deployerPrivateKey);
        address positionManagerAddr =
            vm.envOr("POSITION_MANAGER_ADDRESS", address(0xEF438C4e7E641A74463f715e370869BF2aEE9483));

        vm.startBroadcast(deployerPrivateKey);

        PositionManager lpm = PositionManager(payable(positionManagerAddr));
        console.log("PositionManager:", address(lpm));

        // ─────────────────────────────────────────────────────────────────────────────
        // POSITION INPUTS: tick range + liquidity; amount0/amount1 computed via helper.
        // NOTE: Pool already initialized → we only call modifyLiquidities (no initializePool).
        // ─────────────────────────────────────────────────────────────────────────────

        uint256 liquidity = 10_000;
        int24 tickLower = 0;
        int24 tickUpper = 16140;
        address owner = sender;

        (uint256 amount0FullPrecision, uint256 amount1FullPrecision) =
            getAmountsForLiquidity(tickLower, tickUpper, uint128(liquidity));
        // HTS tokens use 4 decimals: amounts are in raw units (1 token = 1e4 raw). Add ~1% buffer for slippage.
        uint256 amount0 = (amount0FullPrecision * 101) / 100 + 1;
        uint256 amount1 = (amount1FullPrecision * 101) / 100 + 1;

        // Approve PositionManager to pull HTS tokens (4-decimal raw amounts) via transferFrom during SETTLE_PAIR
        require(IERC20Approve(currency0).approve(positionManagerAddr, amount0), "Multicall: approve token0 failed");
        require(IERC20Approve(currency1).approve(positionManagerAddr, amount1), "Multicall: approve token1 failed");

        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION_FROM_DELTAS), uint8(Actions.SETTLE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] =
            abi.encode(key, tickLower, tickUpper, liquidity, uint128(amount0), uint128(amount1), owner, bytes(""));
        params[1] = abi.encode(key.currency0, key.currency1);

        bytes memory unlockData = abi.encode(actions, params);
        uint256 deadline = block.timestamp + 3600;

        // 1. Add liquidity: mint position + settle
        bytes[] memory addCalls = new bytes[](1);
        addCalls[0] = abi.encodeWithSelector(IPositionManager.modifyLiquidities.selector, unlockData, deadline);
        IMulticall_v4(positionManagerAddr).multicall(addCalls);

        uint256 tokenId = lpm.nextTokenId() - 1;
        console.log("Position minted: tokenId", tokenId, "owner", owner);

        // 2. Decrease 25% of liquidity (position keeps 75%)
        uint256 liquidityDecrease = (liquidity * 25) / 100;
        bytes memory decreaseActions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
        bytes[] memory decreaseParams = new bytes[](1);
        decreaseParams[0] = abi.encode(tokenId, liquidityDecrease, uint128(0), uint128(0), bytes(""));
        bytes memory decreaseUnlockData = abi.encode(decreaseActions, decreaseParams);
        bytes[] memory removeCalls = new bytes[](1);
        removeCalls[0] =
            abi.encodeWithSelector(IPositionManager.modifyLiquidities.selector, decreaseUnlockData, deadline);
        IMulticall_v4(positionManagerAddr).multicall(removeCalls);

        console.log(
            "Decreased 25%% liquidity:", liquidityDecrease, "remaining in position:", liquidity - liquidityDecrease
        );

        vm.stopBroadcast();
    }
}
