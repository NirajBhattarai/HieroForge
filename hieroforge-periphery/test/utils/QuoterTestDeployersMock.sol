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
import {IERC20Minimal} from "hieroforge-core/interfaces/IERC20Minimal.sol";
import {MockERC20} from "./MockERC20.sol";

/// @notice Pool setup for Quoter tests using MockERC20 (no HTS). Use for CI and local runs without Hedera node.
abstract contract QuoterTestDeployersMock is Test {
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    int24 internal constant TICK_SPACING = 60;
    uint128 internal constant LIQUIDITY_PER_RANGE = 1e18;

    IPoolManager public manager;
    Router public router;
    Currency internal currency0;
    Currency internal currency1;
    PoolKey public key;

    ModifyLiquidityParams public liquidityParams = ModifyLiquidityParams({
        tickLower: -180, tickUpper: 180, liquidityDelta: int256(uint256(LIQUIDITY_PER_RANGE)), salt: bytes32(0)
    });

    function deployFreshManagerAndRouters() internal {
        manager = new PoolManager();
        router = new Router(manager);
    }

    function deployMockCurrenciesAndPool() internal returns (PoolKey memory _key, PoolId id) {
        MockERC20 mock0 = new MockERC20();
        MockERC20 mock1 = new MockERC20();
        mock0.mint(address(this), 10e18);
        mock1.mint(address(this), 10e18);

        if (address(mock0) < address(mock1)) {
            currency0 = Currency.wrap(address(mock0));
            currency1 = Currency.wrap(address(mock1));
        } else {
            currency0 = Currency.wrap(address(mock1));
            currency1 = Currency.wrap(address(mock0));
        }

        (_key, id) = initPool(currency0, currency1, 3000, TICK_SPACING, SQRT_PRICE_1_1);
        key = _key;

        IERC20Minimal(Currency.unwrap(currency0)).transfer(address(router), 1e18);
        IERC20Minimal(Currency.unwrap(currency1)).transfer(address(router), 1e18);
        router.modifyLiquidity(_key, liquidityParams, "");

        IERC20Minimal(Currency.unwrap(currency0)).transfer(address(router), 1e18);
        IERC20Minimal(Currency.unwrap(currency1)).transfer(address(router), 1e18);
    }

    function initPool(Currency _currency0, Currency _currency1, uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96)
        internal
        returns (PoolKey memory _key, PoolId id)
    {
        _key = PoolKey({
            currency0: _currency0, currency1: _currency1, fee: fee, tickSpacing: tickSpacing, hooks: address(0)
        });
        id = _key.toId();
        manager.initialize(_key, sqrtPriceX96);
    }
}
