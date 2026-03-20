// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Hsc} from "hedera-forking/Hsc.sol";

import {PositionManager} from "../src/PositionManager.sol";
import {IMulticall_v4} from "../src/interfaces/IMulticall_v4.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {Actions} from "../src/libraries/Actions.sol";

/// @notice Debug script for burning a position NFT from PositionManager.
/// It prints ownership + approvals + liquidity before/after and logs revert bytes on failure.
///
/// Required env:
///   PRIVATE_KEY, POSITION_MANAGER_ADDRESS, TOKEN_ID
///
/// Optional env:
///   AMOUNT0_MIN, AMOUNT1_MIN: slippage mins for decrease/burn (default 0)
///   DEADLINE_SECONDS: default 3600
contract DebugRemovePositionManagerScript is Script {
    function _safeOwnerOf(PositionManager pm, uint256 tokenId) internal returns (address) {
        try pm.ownerOf(tokenId) returns (address o) {
            return o;
        } catch {
            return address(0);
        }
    }

    function _safeGetApproved(PositionManager pm, uint256 tokenId) internal returns (address) {
        try pm.getApproved(tokenId) returns (address a) {
            return a;
        } catch {
            return address(0);
        }
    }

    function _safeIsApprovedForAll(PositionManager pm, address owner, address operator) internal returns (bool) {
        try pm.isApprovedForAll(owner, operator) returns (bool v) {
            return v;
        } catch {
            return false;
        }
    }

    function _buildUnlockData(uint256 tokenId, uint128 amount0Min, uint128 amount1Min)
        internal
        pure
        returns (bytes memory unlockData)
    {
        // burn-only: collect fees + withdraw liquidity and burn the NFT
        bytes memory actions = abi.encodePacked(uint8(Actions.BURN_POSITION));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(tokenId, amount0Min, amount1Min, bytes(""));
        unlockData = abi.encode(actions, params);
    }

    function run() external {
        Hsc.htsSetup();

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(pk);

        address pmAddr = vm.envAddress("POSITION_MANAGER_ADDRESS");
        uint256 tokenId = vm.envUint("TOKEN_ID");

        uint128 amount0Min = uint128(vm.envOr("AMOUNT0_MIN", uint256(0)));
        uint128 amount1Min = uint128(vm.envOr("AMOUNT1_MIN", uint256(0)));

        uint256 deadlineSeconds = vm.envOr("DEADLINE_SECONDS", uint256(3600));
        uint256 deadline = block.timestamp + deadlineSeconds;

        PositionManager pm = PositionManager(pmAddr);

        console.log("=== DebugRemovePositionManager ===");
        console.log("pmAddr:", pmAddr);
        console.log("tokenId:", tokenId);
        console.log("amount0Min:", uint256(amount0Min), "amount1Min:", uint256(amount1Min));
        console.log("deadline:", deadline);

        uint128 liquidityBefore = pm.positionLiquidity(tokenId);
        console.log("liquidityBefore (tracked):", uint256(liquidityBefore));

        address owner = _safeOwnerOf(pm, tokenId);
        address approved = owner != address(0) ? _safeGetApproved(pm, tokenId) : address(0);
        bool approvedForAll = owner != address(0) ? _safeIsApprovedForAll(pm, owner, sender) : false;

        console.log("ownerOf:", owner);
        console.log("getApproved:", approved);
        console.log("isApprovedForAll(owner,sender):", approvedForAll);

        bytes memory unlockData = _buildUnlockData(tokenId, amount0Min, amount1Min);

        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(IPositionManager.modifyLiquidities.selector, unlockData, deadline);

        // Execute
        vm.startBroadcast(pk);
        try IMulticall_v4(pmAddr).multicall(calls) {
            console.log("multicall SUCCESS");
        } catch (bytes memory err) {
            console.logBytes(err);
            console.log("multicall REVERTED (see revert bytes above).");
            vm.stopBroadcast();
            return;
        }
        vm.stopBroadcast();

        // Read post-state
        uint128 liquidityAfter = pm.positionLiquidity(tokenId);
        console.log("liquidityAfter (tracked):", uint256(liquidityAfter));

        address newOwner = _safeOwnerOf(pm, tokenId);
        console.log("ownerOf AFTER:", newOwner, "(position not fully burned; 0x0 likely burned)");

        console.log("=== DebugRemovePositionManager done ===");
    }
}

/**
 * TOKEN_ID=2 MODE=0 PERCENT=100 AMOUNT0_MIN=0 AMOUNT1_MIN=0 bash hieroforge-periphery/scripts/debug-remove-position-manager.sh
 *
 * source .env && set +a && \
 * TOKEN_ID=2 MODE=0 PERCENT=100 AMOUNT0_MIN=0 AMOUNT1_MIN=0 \
 * RPC_URL=https://testnet.hashio.io/api \
 * forge script script/DebugRemovePositionManager.s.sol:DebugRemovePositionManagerScript \
 * --rpc-url https://296.rpc.thirdweb.com/${THIRDWEB_API_KEY} \
 * --private-key "$PRIVATE_KEY" \
 * --broadcast --ffi --skip-simulation -vvvv
 */