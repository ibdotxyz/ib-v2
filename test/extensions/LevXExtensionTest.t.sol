// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/Test.sol";
import "../Common.t.sol";

contract LevXExtensionTest is Test, Common {
    using SafeERC20 for IERC20;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address constant wethHolder = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e; // Aave aWETH
    address constant daiHolder = 0x028171bCA77440897B824Ca71D1c56caC55b68A3; // Aave aDAI
    address constant usdtHolder = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503; // Binance-Peg Tokens
    address constant usdcHolder = 0x0A59649758aa4d66E25f08Dd01271e891fe52199; // Maker PSM-USDC-A

    address constant feedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;
    address constant uniswapV2Factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    uint16 internal constant reserveFactor = 1000; // 10%
    uint16 internal constant stableCollateralFactor = 9000; // 90%
    uint16 internal constant wethCollateralFactor = 7000; // 70%

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    ExtensionRegistry extensionRegistry;
    PriceOracle oracle;
    LevXExtension levX;

    IBToken iWETH;
    IBToken iDAI;
    IBToken iUSDT;
    IBToken iUSDC;

    address admin = address(64);
    address user1 = address(128);

    function setUp() public {
        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);
        ib.setMarketConfigurator(address(configurator));

        creditLimitManager = createCreditLimitManager(admin, ib);
        ib.setCreditLimitManager(address(creditLimitManager));

        extensionRegistry = createExtensionRegistry(admin, ib);
        ib.setExtensionRegistry(address(extensionRegistry));

        TripleSlopeRateModel irm = createDefaultIRM();

        (iWETH,) = createAndListERC20Market(WETH, admin, ib, configurator, irm, reserveFactor);
        (iDAI,) = createAndListERC20Market(DAI, admin, ib, configurator, irm, reserveFactor);
        (iUSDT,) = createAndListERC20Market(USDT, admin, ib, configurator, irm, reserveFactor);
        (iUSDC,) = createAndListERC20Market(USDC, admin, ib, configurator, irm, reserveFactor);

        oracle = createPriceOracle(admin, feedRegistry);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, admin, WETH, Denominations.ETH, Denominations.USD);
        setPriceForMarket(oracle, admin, DAI, DAI, Denominations.USD);
        setPriceForMarket(oracle, admin, USDT, USDT, Denominations.USD);
        setPriceForMarket(oracle, admin, USDC, USDC, Denominations.USD);

        setMarketCollateralFactor(admin, configurator, WETH, wethCollateralFactor);
        setMarketCollateralFactor(admin, configurator, DAI, stableCollateralFactor);
        setMarketCollateralFactor(admin, configurator, USDT, stableCollateralFactor);
        setMarketCollateralFactor(admin, configurator, USDC, stableCollateralFactor);

        // Inject liquidity into pool.

        vm.startPrank(wethHolder);
        IERC20(WETH).safeIncreaseAllowance(address(ib), 10000e18);
        ib.supply(wethHolder, WETH, 10000e18);
        vm.stopPrank();

        vm.startPrank(daiHolder);
        IERC20(DAI).safeIncreaseAllowance(address(ib), 10000000e18);
        ib.supply(daiHolder, DAI, 10000000e18);
        vm.stopPrank();

        vm.startPrank(usdtHolder);
        IERC20(USDT).safeIncreaseAllowance(address(ib), 10000000e6);
        ib.supply(usdtHolder, USDT, 10000000e6);
        vm.stopPrank();

        vm.startPrank(usdcHolder);
        IERC20(USDC).safeIncreaseAllowance(address(ib), 10000000e6);
        ib.supply(usdcHolder, USDC, 10000000e6);
        vm.stopPrank();

        // Configure levX.
        levX = createLevXExtension(admin, ib, extensionRegistry, uniswapV2Factory, WETH);

        vm.prank(admin);
        LevXExtension.AssetAllowed[] memory assetAllowed = new LevXExtension.AssetAllowed[](3);
        assetAllowed[0] = LevXExtension.AssetAllowed({asset: WETH, allowed: true});
        assetAllowed[1] = LevXExtension.AssetAllowed({asset: DAI, allowed: true});
        assetAllowed[2] = LevXExtension.AssetAllowed({asset: USDT, allowed: true});
        levX.setAssetAllowed(assetAllowed);

        // Use USDC as collateral.
        vm.prank(usdcHolder);
        IERC20(USDC).safeTransfer(user1, 1000000e6);
    }

    function testLongWethShortDai() public {
        vm.startPrank(user1);
        IERC20(USDC).safeIncreaseAllowance(address(levX), 1000000e6);

        LevXExtension.CollateralData[] memory collateralData = new LevXExtension.CollateralData[](1);
        collateralData[0] = LevXExtension.CollateralData({asset: USDC, amount: 1000000e6});
        levX.open(WETH, 10e18, DAI, 1000000e18, collateralData); // TODO: max output
        vm.stopPrank();

        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        console.log(collateralValue);
        console.log(debtValue);
    }
}
