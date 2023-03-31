// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/Test.sol";
import "../Common.t.sol";

contract IronBankExtensionIntegrationTest is Test, Common {
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
    address constant uniswapV2Factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    uint16 internal constant reserveFactor = 1000; // 10%
    uint16 internal constant stableCollateralFactor = 9000; // 90%
    uint16 internal constant wethCollateralFactor = 7000; // 70%

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    ExtensionRegistry extensionRegistry;
    PriceOracle oracle;
    IronBankExtension extension;

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

        extension = createExtension(admin, ib, extensionRegistry, uniswapV3Factory, uniswapV2Factory, WETH);
    }

    function testSupplyEther() public {
        uint256 poolWethBefore = IERC20(WETH).balanceOf(address(ib));
        uint256 supplyAmount = 10e18;

        vm.prank(user1);
        vm.deal(user1, supplyAmount);
        IronBankExtension.Action[] memory actions = new IronBankExtension.Action[](1);
        actions[0] = IronBankExtension.Action({name: "SUPPLY_NATIVE_TOKEN", data: bytes("")});
        extension.execute{value: supplyAmount}(actions);

        uint256 poolWethAfter = IERC20(WETH).balanceOf(address(ib));
        assertEq(poolWethAfter - poolWethBefore, supplyAmount);
    }

    function testBorrowEther() public {
        prepareBorrow();

        uint256 poolWethBefore = IERC20(WETH).balanceOf(address(ib));
        uint256 borrowAmount = 10e18;

        vm.prank(user1);
        IronBankExtension.Action[] memory actions = new IronBankExtension.Action[](1);
        actions[0] = IronBankExtension.Action({name: "BORROW_NATIVE_TOKEN", data: abi.encode(borrowAmount)});
        extension.execute(actions);

        uint256 poolWethAfter = IERC20(WETH).balanceOf(address(ib));
        assertEq(poolWethBefore - poolWethAfter, borrowAmount);
    }

    function testRedeemEther() public {
        uint256 supplyAmount = 10e18;

        vm.startPrank(user1);
        IERC20(WETH).safeIncreaseAllowance(address(ib), supplyAmount);
        ib.supply(user1, WETH, supplyAmount);
        vm.stopPrank();

        uint256 poolWethBefore = IERC20(WETH).balanceOf(address(ib));

        vm.prank(user1);
        IronBankExtension.Action[] memory actions = new IronBankExtension.Action[](1);
        actions[0] = IronBankExtension.Action({name: "REDEEM_NATIVE_TOKEN", data: abi.encode(supplyAmount)});
        extension.execute(actions);

        uint256 poolWethAfter = IERC20(WETH).balanceOf(address(ib));
        assertEq(poolWethBefore - poolWethAfter, supplyAmount);
    }

    function testRepayEther() public {
        prepareBorrow();

        uint256 borrowAmount = 10e18;

        vm.prank(user1);
        IronBankExtension.Action[] memory actions1 = new IronBankExtension.Action[](1);
        actions1[0] = IronBankExtension.Action({name: "BORROW_NATIVE_TOKEN", data: abi.encode(borrowAmount)});
        extension.execute(actions1);

        uint256 poolWethBefore = IERC20(WETH).balanceOf(address(ib));
        uint256 repayAmount = 5e18;

        vm.prank(user1);
        IronBankExtension.Action[] memory actions2 = new IronBankExtension.Action[](1);
        actions2[0] = IronBankExtension.Action({name: "REPAY_NATIVE_TOKEN", data: bytes("")});
        extension.execute{value: repayAmount}(actions2);

        uint256 poolWethAfter = IERC20(WETH).balanceOf(address(ib));
        assertEq(poolWethAfter - poolWethBefore, repayAmount);
    }

    function testRepayFullEther() public {
        prepareBorrow();

        uint256 borrowAmount = 10e18;

        vm.prank(user1);
        IronBankExtension.Action[] memory actions1 = new IronBankExtension.Action[](1);
        actions1[0] = IronBankExtension.Action({name: "BORROW_NATIVE_TOKEN", data: abi.encode(borrowAmount)});
        extension.execute(actions1);

        uint256 poolWethBefore = IERC20(WETH).balanceOf(address(ib));
        uint256 repayAmount = 12e18;

        vm.prank(user1);
        vm.deal(user1, repayAmount);
        IronBankExtension.Action[] memory actions2 = new IronBankExtension.Action[](1);
        actions2[0] = IronBankExtension.Action({name: "REPAY_NATIVE_TOKEN", data: bytes("")});
        extension.execute{value: repayAmount}(actions2);

        uint256 poolWethAfter = IERC20(WETH).balanceOf(address(ib));
        assertEq(poolWethAfter - poolWethBefore, borrowAmount);
    }

    function testSupplyAndBorrow() public {
        /**
         * Supply 10,000 DAI to borrow 5,000 USDT.
         */
        uint256 supplyAmount = 10000e18;
        uint256 borrowAmount = 5000e6;

        uint256 userUsdtBefore = IERC20(USDT).balanceOf(user1);
        uint256 userDaiBefore = IERC20(DAI).balanceOf(user1);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(extension), supplyAmount);
        IronBankExtension.Action[] memory actions = new IronBankExtension.Action[](2);
        actions[0] = IronBankExtension.Action({name: "ADD_COLLATERAL", data: abi.encode(DAI, supplyAmount)});
        actions[1] = IronBankExtension.Action({name: "BORROW_ASSET", data: abi.encode(USDT, borrowAmount)});
        extension.execute(actions);
        vm.stopPrank();

        uint256 userUsdtAfter = IERC20(USDT).balanceOf(user1);
        uint256 userDaiAfter = IERC20(DAI).balanceOf(user1);

        assertEq(userUsdtAfter - userUsdtBefore, borrowAmount);
        assertEq(userDaiBefore - userDaiAfter, supplyAmount);
    }

    function testLongWethAgainstDaiThruUniV3() public {
        /**
         * Long 100 WETH.
         * Path: WETH -> USDC -> DAI
         */
        uint256 longAmount = 100e18;

        vm.startPrank(user1);
        IERC20(WETH).safeIncreaseAllowance(address(extension), longAmount);

        address[] memory path = new address[](3);
        path[0] = WETH;
        path[1] = USDC;
        path[2] = DAI;
        uint24[] memory fees = new uint24[](2);
        fees[0] = 500; // 0.05%
        fees[1] = 100; // 0.01%
        IronBankExtension.Action[] memory actions1 = new IronBankExtension.Action[](2);
        actions1[0] = IronBankExtension.Action({name: "ADD_COLLATERAL", data: abi.encode(WETH, longAmount)});
        actions1[1] = IronBankExtension.Action({
            name: "LEVERAGE_LONG_THRU_UNISWAP_V3",
            data: abi.encode(WETH, longAmount, DAI, type(uint256).max, path, fees, true)
        });
        extension.execute(actions1);

        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue > 0);

        path[0] = DAI;
        path[1] = USDC;
        path[2] = WETH;
        fees[0] = 100; // 0.01%
        fees[1] = 500; // 0.05%
        IronBankExtension.Action[] memory actions2 = new IronBankExtension.Action[](1);
        actions2[0] = IronBankExtension.Action({
            name: "LEVERAGE_LONG_THRU_UNISWAP_V3",
            data: abi.encode(DAI, type(uint256).max, WETH, type(uint256).max, path, fees, false)
        });
        extension.execute(actions2);

        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue == 0);
        vm.stopPrank();
    }

    function testLongUsdtAgainstWethThruUniV3() public {
        /**
         * Long 100,000 USDT.
         * Path: USDT -> WETH
         */
        uint256 longAmount = 100000e6;

        vm.startPrank(user1);
        IERC20(USDT).safeIncreaseAllowance(address(extension), longAmount);

        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = WETH;
        uint24[] memory fees = new uint24[](1);
        fees[0] = 3000; // 0.3%
        IronBankExtension.Action[] memory actions1 = new IronBankExtension.Action[](2);
        actions1[0] = IronBankExtension.Action({name: "ADD_COLLATERAL", data: abi.encode(USDT, longAmount)});
        actions1[1] = IronBankExtension.Action({
            name: "LEVERAGE_LONG_THRU_UNISWAP_V3",
            data: abi.encode(USDT, longAmount, WETH, type(uint256).max, path, fees, true)
        });
        extension.execute(actions1);

        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue > 0);

        path[0] = WETH;
        path[1] = USDT;
        IronBankExtension.Action[] memory actions2 = new IronBankExtension.Action[](1);
        actions2[0] = IronBankExtension.Action({
            name: "LEVERAGE_LONG_THRU_UNISWAP_V3",
            data: abi.encode(WETH, type(uint256).max, USDT, type(uint256).max, path, fees, false)
        });
        extension.execute(actions2);
        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue == 0);
        vm.stopPrank();
    }

    function testLongDaiAgainstUsdtThruUniV3() public {
        /**
         * Long 100,000 DAI.
         * Path: DAI -> USDC -> USDT
         */
        uint256 longAmount = 100000e18;

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(extension), longAmount);

        address[] memory path = new address[](3);
        path[0] = DAI;
        path[1] = USDC;
        path[2] = USDT;
        uint24[] memory fees = new uint24[](2);
        fees[0] = 100; // 0.01%
        fees[1] = 100; // 0.01%
        IronBankExtension.Action[] memory actions1 = new IronBankExtension.Action[](2);
        actions1[0] = IronBankExtension.Action({name: "ADD_COLLATERAL", data: abi.encode(DAI, longAmount)});
        actions1[1] = IronBankExtension.Action({
            name: "LEVERAGE_LONG_THRU_UNISWAP_V3",
            data: abi.encode(DAI, longAmount, USDT, type(uint256).max, path, fees, true)
        });
        extension.execute(actions1);

        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue > 0);

        path[0] = USDT;
        path[1] = USDC;
        path[2] = DAI;
        IronBankExtension.Action[] memory actions2 = new IronBankExtension.Action[](1);
        actions2[0] = IronBankExtension.Action({
            name: "LEVERAGE_LONG_THRU_UNISWAP_V3",
            data: abi.encode(USDT, type(uint256).max, DAI, type(uint256).max, path, fees, false)
        });
        extension.execute(actions2);
        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue == 0);
        vm.stopPrank();
    }

    function testLongWethAgainstDaiThruUniV2() public {
        /**
         * Long 100 WETH.
         * Path: WETH -> USDC -> DAI
         */
        uint256 longAmount = 100e18;

        vm.startPrank(user1);
        IERC20(WETH).safeIncreaseAllowance(address(extension), longAmount);

        address[] memory path = new address[](3);
        path[0] = WETH;
        path[1] = USDC;
        path[2] = DAI;
        IronBankExtension.Action[] memory actions1 = new IronBankExtension.Action[](2);
        actions1[0] = IronBankExtension.Action({name: "ADD_COLLATERAL", data: abi.encode(WETH, longAmount)});
        actions1[1] = IronBankExtension.Action({
            name: "LEVERAGE_LONG_THRU_UNISWAP_V2",
            data: abi.encode(WETH, longAmount, DAI, type(uint256).max, path, true)
        });
        extension.execute(actions1);

        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue > 0);

        path[0] = DAI;
        path[1] = USDC;
        path[2] = WETH;
        IronBankExtension.Action[] memory actions2 = new IronBankExtension.Action[](1);
        actions2[0] = IronBankExtension.Action({
            name: "LEVERAGE_LONG_THRU_UNISWAP_V2",
            data: abi.encode(DAI, type(uint256).max, WETH, type(uint256).max, path, false)
        });
        extension.execute(actions2);

        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue == 0);
        vm.stopPrank();
    }

    function testLongUsdtAgainstWethThruUniV2() public {
        /**
         * Long 100,000 USDT.
         * Path: USDT -> WETH
         */
        uint256 longAmount = 100000e6;

        vm.startPrank(user1);
        IERC20(USDT).safeIncreaseAllowance(address(extension), longAmount);

        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = WETH;
        IronBankExtension.Action[] memory actions1 = new IronBankExtension.Action[](2);
        actions1[0] = IronBankExtension.Action({name: "ADD_COLLATERAL", data: abi.encode(USDT, longAmount)});
        actions1[1] = IronBankExtension.Action({
            name: "LEVERAGE_LONG_THRU_UNISWAP_V2",
            data: abi.encode(USDT, longAmount, WETH, type(uint256).max, path, true)
        });
        extension.execute(actions1);

        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue > 0);

        path[0] = WETH;
        path[1] = USDT;
        IronBankExtension.Action[] memory actions2 = new IronBankExtension.Action[](1);
        actions2[0] = IronBankExtension.Action({
            name: "LEVERAGE_LONG_THRU_UNISWAP_V2",
            data: abi.encode(WETH, type(uint256).max, USDT, type(uint256).max, path, false)
        });
        extension.execute(actions2);

        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue == 0);
        vm.stopPrank();
    }

    function testLongDaiAgainstUsdtThruUniV2() public {
        /**
         * Long 100,000 DAI.
         * Path: DAI -> USDC -> USDT
         */
        uint256 longAmount = 100000e18;

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(extension), longAmount);

        address[] memory path = new address[](3);
        path[0] = DAI;
        path[1] = USDC;
        path[2] = USDT;
        IronBankExtension.Action[] memory actions1 = new IronBankExtension.Action[](2);
        actions1[0] = IronBankExtension.Action({name: "ADD_COLLATERAL", data: abi.encode(DAI, longAmount)});
        actions1[1] = IronBankExtension.Action({
            name: "LEVERAGE_LONG_THRU_UNISWAP_V2",
            data: abi.encode(DAI, longAmount, USDT, type(uint256).max, path, true)
        });
        extension.execute(actions1);

        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue > 0);

        path[0] = USDT;
        path[1] = USDC;
        path[2] = DAI;
        IronBankExtension.Action[] memory actions2 = new IronBankExtension.Action[](1);
        actions2[0] = IronBankExtension.Action({
            name: "LEVERAGE_LONG_THRU_UNISWAP_V2",
            data: abi.encode(USDT, type(uint256).max, DAI, type(uint256).max, path, false)
        });
        extension.execute(actions2);

        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertTrue(collateralValue > 0);
        assertTrue(debtValue == 0);
        vm.stopPrank();
    }

    function prepareBorrow() internal {
        vm.prank(daiHolder);
        IERC20(DAI).safeTransfer(user1, 1000000e18);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(ib), 1000000e18);
        ib.supply(user1, DAI, 1000000e18);
        ib.enterMarket(user1, DAI);
        vm.stopPrank();
    }
}
