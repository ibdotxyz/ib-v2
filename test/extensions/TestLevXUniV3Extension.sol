// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/Test.sol";
import "../Common.t.sol";

contract LevXUniV3ExtensionTest is Test, Common {
    using SafeERC20 for IERC20;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address constant wethHolder = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e; // Aave aWETH
    address constant daiHolder = 0x028171bCA77440897B824Ca71D1c56caC55b68A3; // Aave aDAI
    address constant usdtHolder = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503; // Binance-Peg Tokens

    address constant feedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;
    address constant uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    uint16 internal constant reserveFactor = 1000; // 10%
    uint16 internal constant stableCollateralFactor = 9000; // 90%
    uint16 internal constant wethCollateralFactor = 7000; // 70%

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    ExtensionRegistry extensionRegistry;
    PriceOracle oracle;
    LevXUniV3Extension levX;

    address admin = address(64);
    address user1 = address(128);

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        uint256 forkId = vm.createFork(url);
        vm.selectFork(forkId);

        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);
        ib.setMarketConfigurator(address(configurator));

        creditLimitManager = createCreditLimitManager(admin, ib);
        ib.setCreditLimitManager(address(creditLimitManager));

        extensionRegistry = createExtensionRegistry(admin, ib);
        ib.setExtensionRegistry(address(extensionRegistry));

        TripleSlopeRateModel irm = createDefaultIRM();

        createAndListERC20Market(WETH, admin, ib, configurator, irm, reserveFactor);
        createAndListERC20Market(DAI, admin, ib, configurator, irm, reserveFactor);
        createAndListERC20Market(USDT, admin, ib, configurator, irm, reserveFactor);

        oracle = createPriceOracle(admin, feedRegistry);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, admin, WETH, Denominations.ETH, Denominations.USD);
        setPriceForMarket(oracle, admin, DAI, DAI, Denominations.USD);
        setPriceForMarket(oracle, admin, USDT, USDT, Denominations.USD);

        setMarketCollateralFactor(admin, configurator, WETH, wethCollateralFactor);
        setMarketCollateralFactor(admin, configurator, DAI, stableCollateralFactor);
        setMarketCollateralFactor(admin, configurator, USDT, stableCollateralFactor);

        // Inject liquidity into pool and user1.
        vm.startPrank(wethHolder);
        IERC20(WETH).safeIncreaseAllowance(address(ib), 10000e18);
        ib.supply(wethHolder, WETH, 10000e18);
        IERC20(WETH).safeTransfer(user1, 10000e18);
        vm.stopPrank();

        vm.startPrank(daiHolder);
        IERC20(DAI).safeIncreaseAllowance(address(ib), 10000000e18);
        ib.supply(daiHolder, DAI, 10000000e18);
        IERC20(DAI).safeTransfer(user1, 10000000e18);
        vm.stopPrank();

        vm.startPrank(usdtHolder);
        IERC20(USDT).safeIncreaseAllowance(address(ib), 10000000e6);
        ib.supply(usdtHolder, USDT, 10000000e6);
        IERC20(USDT).safeTransfer(user1, 10000000e6);
        vm.stopPrank();

        // Configure levX.
        levX = createLevXUniV3Extension(admin, ib, extensionRegistry, uniswapV3Factory, WETH);

        vm.prank(admin);
        LevXUniV3Extension.AssetAllowed[] memory assetAllowed = new LevXUniV3Extension.AssetAllowed[](3);
        assetAllowed[0] = LevXUniV3Extension.AssetAllowed({asset: WETH, allowed: true});
        assetAllowed[1] = LevXUniV3Extension.AssetAllowed({asset: DAI, allowed: true});
        assetAllowed[2] = LevXUniV3Extension.AssetAllowed({asset: USDT, allowed: true});
        levX.setAssetAllowed(assetAllowed);
    }

    function testLongWethShortDai() public {
        uint256 longAmount = 100e18;

        vm.startPrank(user1);
        IERC20(WETH).safeIncreaseAllowance(address(levX), longAmount);

        uint24 fee1 = 500; // 0.05%
        uint24 fee2 = 100; // 0.01%
        bytes memory path = abi.encodePacked(WETH, fee1, USDC, fee2, DAI);
        LevXUniV3Extension.CollateralData[] memory collateralData = new LevXUniV3Extension.CollateralData[](1);
        collateralData[0] = LevXUniV3Extension.CollateralData({asset: WETH, amount: longAmount});
        levX.open(WETH, longAmount, DAI, type(uint256).max, path, collateralData);

        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue > 0);

        path = abi.encodePacked(DAI, fee2, USDC, fee1, WETH);
        levX.close(DAI, type(uint256).max, WETH, type(uint256).max, path);
        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue == 0);
        vm.stopPrank();
    }

    function testLongUsdtShortWeth() public {
        uint256 longAmount = 100000e6;

        vm.startPrank(user1);
        IERC20(USDT).safeIncreaseAllowance(address(levX), longAmount);

        uint24 fee = 3000; // 0.3%
        bytes memory path = abi.encodePacked(USDT, fee, WETH);
        LevXUniV3Extension.CollateralData[] memory collateralData = new LevXUniV3Extension.CollateralData[](1);
        collateralData[0] = LevXUniV3Extension.CollateralData({asset: USDT, amount: longAmount});
        levX.open(USDT, longAmount, WETH, type(uint256).max, path, collateralData);

        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue > 0);

        path = abi.encodePacked(WETH, fee, USDT);
        levX.close(WETH, type(uint256).max, USDT, type(uint256).max, path);
        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue == 0);
        vm.stopPrank();
    }

    function testLongDaiShortUsdt() public {
        uint256 longAmount = 100000e18;

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(levX), longAmount);

        uint24 fee1 = 100; // 0.01%
        uint24 fee2 = 100; // 0.01%
        bytes memory path = abi.encodePacked(DAI, fee1, USDC, fee2, USDT);
        LevXUniV3Extension.CollateralData[] memory collateralData = new LevXUniV3Extension.CollateralData[](1);
        collateralData[0] = LevXUniV3Extension.CollateralData({asset: DAI, amount: longAmount});
        levX.open(DAI, longAmount, USDT, type(uint256).max, path, collateralData);

        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue > 0);

        path = abi.encodePacked(USDT, fee2, USDC, fee1, DAI);
        levX.close(USDT, type(uint256).max, DAI, type(uint256).max, path);
        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue == 0);
        vm.stopPrank();
    }
}
