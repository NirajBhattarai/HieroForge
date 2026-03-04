// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "../../src/PoolManager.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {PoolId} from "../../src/types/PoolId.sol";
import {Currency} from "../../src/types/Currency.sol";
import {ModifyLiquidityParams} from "../../src/types/ModifyLiquidityParams.sol";
import {TickMath} from "../../src/libraries/TickMath.sol";
import {Constants} from "./Constants.sol";
import {ModifyLiquidityRouter} from "./ModifyLiquidityRouter.sol";
import {htsSetup} from "hedera-forking/htsSetup.sol";
import {IHederaTokenService} from "hedera-forking/IHederaTokenService.sol";
import {HederaResponseCodes} from "hedera-forking/HederaResponseCodes.sol";
import {IERC20} from "hedera-forking/IERC20.sol";

/// @notice Test deployers and helpers for PoolManager tests (Uniswap v4-style)
contract Deployers is Test {
    // Helpful test constants (from Constants.sol)
    bytes internal constant ZERO_BYTES = Constants.ZERO_BYTES;
    uint160 internal constant SQRT_PRICE_1_1 = Constants.SQRT_PRICE_1_1;
    uint160 internal constant SQRT_PRICE_1_2 = Constants.SQRT_PRICE_1_2;
    uint160 internal constant SQRT_PRICE_1_4 = Constants.SQRT_PRICE_1_4;
    uint160 internal constant SQRT_PRICE_2_1 = Constants.SQRT_PRICE_2_1;
    uint160 internal constant SQRT_PRICE_4_1 = Constants.SQRT_PRICE_4_1;

    uint160 public minPriceLimit = TickMath.minSqrtPrice() + 1;
    uint160 public maxPriceLimit = TickMath.maxSqrtPrice() - 1;

    // Default liquidity params for add / remove
    ModifyLiquidityParams public LIQUIDITY_PARAMS = ModifyLiquidityParams({
        owner: address(0), // set in test or in init
        tickLower: -120,
        tickUpper: 120,
        liquidityDelta: 1e18,
        tickSpacing: 60,
        salt: bytes32(0)
    });
    ModifyLiquidityParams public REMOVE_LIQUIDITY_PARAMS = ModifyLiquidityParams({
        owner: address(0), tickLower: -120, tickUpper: 120, liquidityDelta: -1e18, tickSpacing: 60, salt: bytes32(0)
    });

    // Global state
    IPoolManager public manager;
    ModifyLiquidityRouter public modifyLiquidityRouter;
    Currency internal currency0;
    Currency internal currency1;
    PoolKey public key;
    PoolKey public uninitializedKey;

    function deployFreshManager() internal virtual {
        manager = new PoolManager();
    }

    function deployFreshManagerAndRouters() internal {
        deployFreshManager();
        modifyLiquidityRouter = new ModifyLiquidityRouter(manager);
    }

    /// @notice Deploy two HTS fungible tokens via HTS precompile at 0x167; use this as treasury. Sort by address (currency0 < currency1).
    /// @dev Requires htsSetup() and ffi. Run: forge test --match-path test/PoolManager.modifyLiquidity.t.sol --ffi
    function deployMintAndApprove2CurrenciesHTS() internal returns (Currency, Currency) {
        htsSetup();
        vm.deal(address(this), 1 ether);
        address hts = address(0x167);

        // Create first HTS token (minimal HederaToken; treasury = this so we receive initial supply)
        IHederaTokenService.HederaToken memory tokenA_ = _minimalHederaToken("TokenA", "TKA", address(this));
        (int64 codeA, address tokenA) =
            IHederaTokenService(hts).createFungibleToken{value: 1000}(tokenA_, 10_000_000_000, 18);
        require(
            codeA == int64(int32(HederaResponseCodes.SUCCESS)) && tokenA != address(0), "HTS: token A creation failed"
        );

        // Create second HTS token
        IHederaTokenService.HederaToken memory tokenB_ = _minimalHederaToken("TokenB", "TKB", address(this));
        (int64 codeB, address tokenB) =
            IHederaTokenService(hts).createFungibleToken{value: 1000}(tokenB_, 10_000_000_000, 18);
        require(
            codeB == int64(int32(HederaResponseCodes.SUCCESS)) && tokenB != address(0), "HTS: token B creation failed"
        );

        if (tokenA < tokenB) {
            currency0 = Currency.wrap(tokenA);
            currency1 = Currency.wrap(tokenB);
        } else {
            currency0 = Currency.wrap(tokenB);
            currency1 = Currency.wrap(tokenA);
        }

        // Approve router (HTS tokens expose ERC20 via precompile/redirect)
        IERC20(Currency.unwrap(currency0)).approve(address(modifyLiquidityRouter), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(modifyLiquidityRouter), type(uint256).max);

        return (currency0, currency1);
    }

    function _minimalHederaToken(string memory name_, string memory symbol_, address treasury_)
        internal
        pure
        returns (IHederaTokenService.HederaToken memory)
    {
        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](0);
        IHederaTokenService.Expiry memory expiry = IHederaTokenService.Expiry(0, address(0), 0);
        return IHederaTokenService.HederaToken({
            name: name_,
            symbol: symbol_,
            treasury: treasury_,
            memo: "",
            tokenSupplyType: true,
            maxSupply: 20_000_000_000,
            freezeDefault: false,
            tokenKeys: keys,
            expiry: expiry
        });
    }

    /// @notice Initialize a pool (no liquidity added)
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

    /// @notice Initialize manager, routers, two HTS currencies, one initialized pool. Requires ffi: forge test ... --ffi
    function initializeManagerRoutersAndPools() internal {
        deployFreshManagerAndRouters();
        deployMintAndApprove2CurrenciesHTS();
        _finishInitPools();
    }

    function _finishInitPools() internal {
        (key,) = initPool(currency0, currency1, 3000, 60, SQRT_PRICE_1_1);
        uninitializedKey =
            PoolKey({currency0: currency0, currency1: currency1, fee: 100, tickSpacing: 60, hooks: address(0)});
    }
}
