// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

/// @notice Minimal ERC20 for step-by-step deploy (compatible with IERC20Minimal used by pool/PositionManager)
contract MockERC20Deploy {
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

/// @notice Step 2: Deploy two mock ERC20 tokens and mint to deployer. Use addresses as CURRENCY0_ADDRESS, CURRENCY1_ADDRESS.
/// Usage:
///   forge script script/DeployMockTokens.s.sol:DeployMockTokensScript --rpc-url <rpc> --broadcast --private-key $PRIVATE_KEY
contract DeployMockTokensScript is Script {
    uint256 constant MINT_AMOUNT = 10e18;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        MockERC20Deploy token0 = new MockERC20Deploy();
        MockERC20Deploy token1 = new MockERC20Deploy();
        token0.mint(deployer, MINT_AMOUNT);
        token1.mint(deployer, MINT_AMOUNT);

        vm.stopBroadcast();

        (address c0, address c1) =
            address(token0) < address(token1) ? (address(token0), address(token1)) : (address(token1), address(token0));
        console.log("Token0:", address(token0));
        console.log("Token1:", address(token1));
        console.log("CURRENCY0_ADDRESS (use for pool):", c0);
        console.log("CURRENCY1_ADDRESS (use for pool):", c1);
        console.log("Minted per token:", MINT_AMOUNT);
    }
}
