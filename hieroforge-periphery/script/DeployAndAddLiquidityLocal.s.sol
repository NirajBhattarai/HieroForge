// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PoolManager} from "hieroforge-core/PoolManager.sol";
import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {Currency} from "hieroforge-core/types/Currency.sol";
import {IERC20Minimal} from "hieroforge-core/interfaces/IERC20Minimal.sol";
import {PositionManager} from "../src/PositionManager.sol";
import {IPositionManager} from "../src/interfaces/IPositionManager.sol";
import {Actions} from "../src/libraries/Actions.sol";
import {Hsc} from "hedera-forking/Hsc.sol";

/// @notice Minimal ERC20 for local deploy script (no test dependency)
contract MockERC20Local {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @notice One-shot: deploy PoolManager, mock tokens, PositionManager, then add liquidity on local chain.
/// Usage:
///   Local Hedera (e.g. localhost:7546): ./scripts/run-deploy-and-add-liquidity-local.sh
///   Or: forge script script/DeployAndAddLiquidityLocal.s.sol:DeployAndAddLiquidityLocalScript --rpc-url http://localhost:7546 --broadcast --private-key $PRIVATE_KEY
contract DeployAndAddLiquidityLocalScript is Script {
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function run() external {
        uint256 deployerPrivateKey =
            vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy PoolManager (core)
        PoolManager poolManager = new PoolManager();
        console.log("PoolManager:", address(poolManager));

        // 2. Deploy mock tokens and mint
        MockERC20Local token0 = new MockERC20Local();
        MockERC20Local token1 = new MockERC20Local();
        uint256 mintAmount = 10e18;
        token0.mint(deployer, mintAmount);
        token1.mint(deployer, mintAmount);
        console.log("Token0:", address(token0));
        console.log("Token1:", address(token1));

        // 3. HTS emulation at 0x167 (hedera-forking; requires --ffi)
        Hsc.htsSetup();

        // 4. Deploy PositionManager
        PositionManager lpm = new PositionManager(IPoolManager(address(poolManager)));
        console.log("PositionManager:", address(lpm));

        // 5. Pool key (currency0 < currency1)
        address a0 = address(token0);
        address a1 = address(token1);
        (address currency0, address currency1) = a0 < a1 ? (a0, a1) : (a1, a0);
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });

        // 6. Initialize pool at 1:1
        poolManager.initialize(poolKey, SQRT_PRICE_1_1);
        console.log("Pool initialized at 1:1");

        // 7. Transfer tokens to PositionManager
        uint256 amount0 = 1e18;
        uint256 amount1 = 1e18;
        require(IERC20Minimal(currency0).transfer(address(lpm), amount0), "transfer0");
        require(IERC20Minimal(currency1).transfer(address(lpm), amount1), "transfer1");
        console.log("Transferred token0 and token1 to PositionManager");

        // 8. Mint position
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION));
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(
            poolKey,
            int24(-120),
            int24(120),
            uint256(1000000000000000000),
            uint128(amount0),
            uint128(amount1),
            deployer,
            bytes("")
        );
        bytes memory unlockData = abi.encode(actions, params);
        uint256 deadline = block.timestamp + 3600;
        lpm.modifyLiquidities(unlockData, deadline);

        uint256 tokenId = lpm.nextTokenId() - 1;
        console.log("Position minted: tokenId", tokenId, "owner", deployer);

        vm.stopBroadcast();
    }
}
