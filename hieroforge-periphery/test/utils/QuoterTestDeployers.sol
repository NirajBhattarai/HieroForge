// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "hieroforge-core/PoolManager.sol";
import {IPoolManager} from "hieroforge-core/interfaces/IPoolManager.sol";
import {Router} from "hieroforge-core/Router.sol";
import {PoolKey} from "hieroforge-core/types/PoolKey.sol";
import {PoolId} from "hieroforge-core/types/PoolId.sol";
import {Currency} from "hieroforge-core/types/Currency.sol";
import {ModifyLiquidityParams} from "hieroforge-core/types/ModifyLiquidityParams.sol";
import {TickMath} from "hieroforge-core/libraries/TickMath.sol";
import {htsSetup} from "hedera-forking/htsSetup.sol";
import {IHederaTokenService} from "hedera-forking/IHederaTokenService.sol";
import {HederaResponseCodes} from "hedera-forking/HederaResponseCodes.sol";
import {IERC20} from "hedera-forking/IERC20.sol";

/// @notice HTS + pool setup for Quoter tests. Use with --ffi. Run against local node: --fork-url http://localhost:7546
abstract contract QuoterTestDeployers is Test {
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    int24 internal constant TICK_SPACING = 60;
    uint128 internal constant LIQUIDITY_PER_RANGE = 1e18;
    /// @dev HTS tokens created with initialTotalSupply 10e9; keep transfers within that (leave headroom for test transfers)
    uint256 internal constant HTS_FUND_AMOUNT = 3e9;

    IPoolManager public manager;
    Router public router;
    Currency internal currency0;
    Currency internal currency1;
    PoolKey public key;

    ModifyLiquidityParams public LIQUIDITY_PARAMS = ModifyLiquidityParams({
        owner: address(0),
        tickLower: -180,
        tickUpper: 180,
        liquidityDelta: 1e9, // small L so token amounts fit in HTS supply (10e9) and router funding (3e9)
        tickSpacing: TICK_SPACING,
        salt: bytes32(0)
    });

    function deployFreshManagerAndRouters() internal {
        manager = new PoolManager();
        router = new Router(manager);
    }

    /// @dev Requires htsSetup() in setUp and --ffi. Run: forge test --match-contract QuoterTest --ffi
    ///      Against local Hedera node: forge test --match-contract QuoterTest --fork-url http://localhost:7546 --ffi
    function deployMintAndApprove2CurrenciesHTS() internal returns (Currency, Currency) {
        htsSetup();
        vm.deal(address(this), 1 ether);
        address hts = address(0x167);

        IHederaTokenService.HederaToken memory tokenA_ = _minimalHederaToken("TokenA", "TKA", address(this));
        (int64 codeA, address tokenA) =
            IHederaTokenService(hts).createFungibleToken{value: 1000}(tokenA_, 10_000_000_000, 18);
        require(
            codeA == int64(int32(HederaResponseCodes.SUCCESS)) && tokenA != address(0), "HTS: token A creation failed"
        );

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

        // Workaround: hedera-forking may not credit treasury when running from periphery. Force balance via vm.store
        // using the same slot formula as HtsSystemContractJson for unknown accounts (deterministic accountId).
        _ensureTreasuryBalance(Currency.unwrap(currency0), 10_000_000_000);
        _ensureTreasuryBalance(Currency.unwrap(currency1), 10_000_000_000);

        IERC20(Currency.unwrap(currency0)).approve(address(router), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(router), type(uint256).max);

        return (currency0, currency1);
    }

    /// @dev Sets treasury balance in HTS token storage so transfers succeed when mint did not credit us.
    /// Slot = same as HtsSystemContract._balanceOfSlot with accountId = uint32(bytes4(keccak256(abi.encodePacked(account)))).
    function _ensureTreasuryBalance(address token, uint256 amount) internal {
        uint32 accountId = uint32(bytes4(keccak256(abi.encodePacked(address(this)))));
        bytes32 balanceSlot = bytes32(abi.encodePacked(IERC20.balanceOf.selector, uint192(0), accountId));
        vm.store(token, balanceSlot, bytes32(amount));
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

    /// @notice Init pool and add liquidity so swaps and quotes can run
    function setupPoolWithLiquidity() internal returns (PoolKey memory _key, PoolId id) {
        (_key, id) = initPool(currency0, currency1, 3000, TICK_SPACING, SQRT_PRICE_1_1);
        key = _key;

        LIQUIDITY_PARAMS.owner = address(router);
        require(IERC20(Currency.unwrap(currency0)).transfer(address(router), HTS_FUND_AMOUNT), "fund0");
        require(IERC20(Currency.unwrap(currency1)).transfer(address(router), HTS_FUND_AMOUNT), "fund1");
        router.modifyLiquidity(_key, LIQUIDITY_PARAMS, "");

        require(IERC20(Currency.unwrap(currency0)).transfer(address(router), HTS_FUND_AMOUNT), "fund0-swap");
        require(IERC20(Currency.unwrap(currency1)).transfer(address(router), HTS_FUND_AMOUNT), "fund1-swap");
    }
}
