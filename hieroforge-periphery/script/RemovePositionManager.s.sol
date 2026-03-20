// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Hsc} from "hedera-forking/Hsc.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {PositionManager} from "../src/PositionManager.sol";
import {IMulticall_v4} from "../src/interfaces/IMulticall_v4.sol";
import {IPoolInitializer_v4} from "../src/interfaces/IPoolInitializer_v4.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {Currency} from "hieroforge-core/types/Currency.sol";
import {IERC20Minimal} from "hieroforge-core/interfaces/IERC20Minimal.sol";
import {Actions} from "../src/libraries/Actions.sol";

/// @notice Mint a PositionManager position (optional) then remove partial and optionally burn.
///
/// Logic:
/// - If `TOKEN_ID` is provided: remove liquidity for that NFT.
/// - If `TOKEN_ID` is not provided (0):
///     - If `CURRENCY0_ADDRESS/CURRENCY1_ADDRESS` and `AMOUNT0/AMOUNT1` are provided: mint a new position,
///       then immediately remove liquidity by `PERCENT` (partial-first use case).
///     - Otherwise: attempt to auto-select the latest position owned by signer.
///
/// Second run:
/// - Use `TOKEN_ID=<the one printed from run 1>` and set `PERCENT=100` to remove all and burn the NFT.
///
/// Required env:
///   PRIVATE_KEY, POSITION_MANAGER_ADDRESS
///
/// Remove-only env:
///   TOKEN_ID
///
/// Mint+partial env:
///   CURRENCY0_ADDRESS, CURRENCY1_ADDRESS, AMOUNT0, AMOUNT1
///
/// Optional env:
///   PERCENT (default 100; 1..100)
///   BURN_AFTER (default auto: true when PERCENT=100, otherwise false)
///   FEE (default 3000), TICK_SPACING (default 60), TICK_LOWER (default -120), TICK_UPPER (default 120)
///   LIQUIDITY (default 100_000_000)
///   OWNER (default signer)
///   SKIP_TRANSFER (default 0), SKIP_BALANCE_CHECK (default 0)
///   AMOUNT0_MIN (default 0), AMOUNT1_MIN (default 0), DEADLINE_SECONDS (default 3600)
contract RemovePositionManagerScript is Script {
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function _findLatestOwnedToken(PositionManager pm, address owner) internal view returns (uint256) {
        uint256 nextTokenId = pm.nextTokenId();
        if (nextTokenId <= 1) return 0;
        for (uint256 id = nextTokenId - 1; id >= 1; id--) {
            try pm.ownerOf(id) returns (address tokenOwner) {
                if (tokenOwner == owner) return id;
            } catch {}
            if (id == 1) break;
        }
        return 0;
    }

    function _mintPosition(
        PositionManager pm,
        address sender,
        uint256 amount0,
        uint256 amount1,
        address c0,
        address c1,
        uint256 liquidity,
        uint24 fee,
        int24 tickSpacing,
        int24 tickLower,
        int24 tickUpper,
        address owner
    ) internal returns (uint256 tokenId) {
        require(c0 != address(0) && c1 != address(0), "mint requires currencies");
        require(amount0 > 0 || amount1 > 0, "mint requires AMOUNT0/AMOUNT1");

        // Canonical order required by PoolKey encoding.
        (address currency0, address currency1) = c0 < c1 ? (c0, c1) : (c1, c0);
        address amount0Currency = currency0;
        uint256 amount0ForCurrency0 = amount0Currency == c0 ? amount0 : amount1;
        uint256 amount1ForCurrency1 = amount0Currency == c0 ? amount1 : amount0;

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: address(0)
        });

        // Optionally validate sender balances to fail with a clear message.
        bool skipBalanceCheck = vm.envOr("SKIP_BALANCE_CHECK", uint256(0)) == 1;
        if (!skipBalanceCheck) {
            uint256 bal0 = IERC20Minimal(currency0).balanceOf(sender);
            uint256 bal1 = IERC20Minimal(currency1).balanceOf(sender);
            require(amount0ForCurrency0 == 0 || bal0 >= amount0ForCurrency0, "mint: insufficient currency0 balance");
            require(amount1ForCurrency1 == 0 || bal1 >= amount1ForCurrency1, "mint: insufficient currency1 balance");
        } else {
            console.log("SKIP_BALANCE_CHECK=1: skipping sender balance check");
        }

        bool skipTransfer = vm.envOr("SKIP_TRANSFER", uint256(0)) == 1;
        if (!skipTransfer) {
            if (amount0ForCurrency0 > 0) {
                require(IERC20Minimal(currency0).transfer(address(pm), amount0ForCurrency0), "mint: transfer currency0 failed");
            }
            if (amount1ForCurrency1 > 0) {
                require(IERC20Minimal(currency1).transfer(address(pm), amount1ForCurrency1), "mint: transfer currency1 failed");
            }
        } else {
            console.log("SKIP_TRANSFER=1: assuming tokens already sent to PositionManager");
        }

        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory mintParams = new bytes[](1);
        mintParams[0] =
            abi.encode(poolKey, tickLower, tickUpper, liquidity, uint128(amount0ForCurrency0), uint128(amount1ForCurrency1), owner, bytes(""));
        bytes memory unlockData = abi.encode(actions, mintParams);

        uint256 deadline = block.timestamp + vm.envOr("DEADLINE_SECONDS", uint256(3600));

        // Initialize pool + mint in one multicall.
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(IPoolInitializer_v4.initializePool.selector, poolKey, SQRT_PRICE_1_1);
        calls[1] = abi.encodeWithSelector(IPositionManager.modifyLiquidities.selector, unlockData, deadline);

        // broadcast happens by caller
        IMulticall_v4(address(pm)).multicall(calls);

        return pm.nextTokenId() - 1;
    }

    function run() external {
        Hsc.htsSetup();

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(pk);
        address pmAddr = vm.envAddress("POSITION_MANAGER_ADDRESS");

        uint256 tokenId = vm.envOr("TOKEN_ID", uint256(0));
        PositionManager pm = PositionManager(pmAddr);

        address owner = vm.envOr("OWNER", sender);
        uint256 percent = vm.envOr("PERCENT", uint256(100));
        require(percent > 0 && percent <= 100, "PERCENT must be 1..100");

        // Mint if tokenId was not provided and mint env vars are present.
        if (tokenId == 0) {
            address c0 = vm.envOr("CURRENCY0_ADDRESS", address(0));
            address c1 = vm.envOr("CURRENCY1_ADDRESS", address(0));
            uint256 amount0 = vm.envOr("AMOUNT0", uint256(0));
            uint256 amount1 = vm.envOr("AMOUNT1", uint256(0));

            if (c0 != address(0) && c1 != address(0) && (amount0 > 0 || amount1 > 0)) {
                uint256 liquidity = vm.envOr("LIQUIDITY", uint256(100_000_000));
                uint24 fee = uint24(vm.envOr("FEE", uint256(3000)));
                int24 tickSpacing = int24(uint24(vm.envOr("TICK_SPACING", uint256(60))));
                int24 tickLower = int24(vm.envOr("TICK_LOWER", int256(-120)));
                int24 tickUpper = int24(vm.envOr("TICK_UPPER", int256(120)));

                require(owner == sender, "mint+remove in one script requires OWNER=signer");
                console.log("Minting new position (remove after)...");
                console.log("  currencies:", c0, c1);
                console.log("  amounts:", amount0, amount1);
                console.log("  liquidity(L):", liquidity);

                vm.startBroadcast(pk);
                tokenId = _mintPosition(pm, sender, amount0, amount1, c0, c1, liquidity, fee, tickSpacing, tickLower, tickUpper, owner);
                vm.stopBroadcast();

                console.log("Minted tokenId:", tokenId);
                console.log("Remaining liquidity (pre-remove):", uint256(pm.positionLiquidity(tokenId)));
            } else {
                tokenId = _findLatestOwnedToken(pm, sender);
                require(tokenId != 0, "no position owned by signer and no mint env provided");
            }
        }

        bool burnAfter = percent == 100 ? true : vm.envOr("BURN_AFTER", false);
        uint128 amount0Min = uint128(vm.envOr("AMOUNT0_MIN", uint256(0)));
        uint128 amount1Min = uint128(vm.envOr("AMOUNT1_MIN", uint256(0)));
        uint256 deadlineSeconds = vm.envOr("DEADLINE_SECONDS", uint256(3600));
        uint256 deadline = block.timestamp + deadlineSeconds;

        uint128 totalLiquidity = PositionManager(pmAddr).positionLiquidity(tokenId);
        uint256 decLiquidity = (uint256(totalLiquidity) * percent) / 100;

        console.log("PositionManager:", pmAddr);
        console.log("TokenId:", tokenId);
        console.log("Total liquidity:", uint256(totalLiquidity));
        console.log("Decrease percent:", percent);
        console.log("Decrease liquidity:", decLiquidity);
        console.log("Burn after:", burnAfter);

        uint256 stepCount = (decLiquidity > 0 ? 1 : 0) + (burnAfter ? 1 : 0);
        require(stepCount > 0, "nothing to do");

        bytes[] memory params = new bytes[](stepCount);
        bytes memory actions;
        uint256 i = 0;

        if (decLiquidity > 0) {
            actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY));
            params[i++] = abi.encode(tokenId, decLiquidity, amount0Min, amount1Min, bytes(""));
        }
        if (burnAfter) {
            actions = bytes.concat(actions, bytes1(uint8(Actions.BURN_POSITION)));
            params[i++] = abi.encode(tokenId, amount0Min, amount1Min, bytes(""));
        }

        bytes memory unlockData = abi.encode(actions, params);
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(IPositionManager.modifyLiquidities.selector, unlockData, deadline);

        vm.startBroadcast(pk);
        IMulticall_v4(pmAddr).multicall(calls);
        vm.stopBroadcast();

        uint128 afterLiquidity = PositionManager(pmAddr).positionLiquidity(tokenId);
        console.log("Tracked liquidity after:", uint256(afterLiquidity));
    }
}
