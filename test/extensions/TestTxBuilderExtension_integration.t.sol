// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/Test.sol";
import "../Common.t.sol";

interface StEthInterface {
    function submit(address _referral) external payable;
}

contract TxBuilderExtensionIntegrationTest is Test, Common {
    using SafeERC20 for IERC20;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address constant feedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;

    uint16 internal constant reserveFactor = 1000; // 10%
    uint16 internal constant stableCollateralFactor = 9000; // 90%
    uint16 internal constant wethCollateralFactor = 7000; // 70%
    uint16 internal constant wstethCollateralFactor = 7000; // 70%

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    PriceOracle oracle;
    TxBuilderExtension extension;

    PToken pDAI;

    address admin = address(64);
    address user1 = address(128);

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        uint256 forkId = vm.createFork(url);
        vm.selectFork(forkId);

        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);

        vm.prank(admin);
        ib.setMarketConfigurator(address(configurator));

        creditLimitManager = createCreditLimitManager(admin, ib);

        vm.prank(admin);
        ib.setCreditLimitManager(address(creditLimitManager));

        TripleSlopeRateModel irm = createDefaultIRM();

        // List WETH, DAI, USDT and WSTETH.
        createAndListERC20Market(WETH, admin, ib, configurator, irm, reserveFactor);
        createAndListERC20Market(DAI, admin, ib, configurator, irm, reserveFactor);
        createAndListERC20Market(USDT, admin, ib, configurator, irm, reserveFactor);
        createAndListERC20Market(WSTETH, admin, ib, configurator, irm, reserveFactor);

        // List pDAI.
        pDAI = createPToken(admin, DAI);
        IBToken ibToken = createIBToken(admin, address(ib), address(pDAI));

        vm.prank(admin);
        configurator.listPTokenMarket(address(pDAI), address(ibToken), address(irm), reserveFactor);

        // Setup price oracle.
        oracle = createPriceOracle(admin, feedRegistry, STETH, WSTETH);

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, admin, WETH, Denominations.ETH, Denominations.USD);
        setPriceForMarket(oracle, admin, DAI, DAI, Denominations.USD);
        setPriceForMarket(oracle, admin, USDT, USDT, Denominations.USD);
        setPriceForMarket(oracle, admin, address(pDAI), DAI, Denominations.USD);

        // Set collateral factors.
        configureMarketAsCollateral(admin, configurator, WETH, wethCollateralFactor);
        configureMarketAsCollateral(admin, configurator, DAI, stableCollateralFactor);
        configureMarketAsCollateral(admin, configurator, USDT, stableCollateralFactor);
        configureMarketAsCollateral(admin, configurator, WSTETH, wstethCollateralFactor);
        configureMarketAsCollateral(admin, configurator, address(pDAI), stableCollateralFactor);

        extension = createTxBuilderExtension(admin, ib, WETH, STETH, WSTETH);

        // Give some ether to user1.
        vm.deal(user1, 10000e18);

        // User1 converts some ether to stETH.
        vm.prank(user1);
        StEthInterface(STETH).submit{value: 1000e18}(address(0));

        // Give some tokens to admin.
        deal(WETH, admin, 10000e18);
        deal(WSTETH, admin, 10000e18);
        deal(DAI, admin, 10000000e18);
        deal(USDT, admin, 10000000e6);

        // Admin supplies some liquidity to Iron Bank.
        vm.startPrank(admin);
        IERC20(WETH).safeIncreaseAllowance(address(ib), 10000e18);
        ib.supply(admin, admin, WETH, 10000e18);
        IERC20(WSTETH).safeIncreaseAllowance(address(ib), 10000e18);
        ib.supply(admin, admin, WSTETH, 10000e18);
        IERC20(DAI).safeIncreaseAllowance(address(ib), 10000000e18);
        ib.supply(admin, admin, DAI, 10000000e18);
        IERC20(USDT).safeIncreaseAllowance(address(ib), 10000000e6);
        ib.supply(admin, admin, USDT, 10000000e6);
        vm.stopPrank();

        // User1 authorizes the extension.
        vm.prank(user1);
        ib.setUserExtension(address(extension), true);
    }

    function testSupplyEther() public {
        uint256 poolWethBefore = IERC20(WETH).balanceOf(address(ib));
        uint256 user1EthBefore = user1.balance;
        uint256 supplyAmount = 10e18;

        vm.prank(user1);
        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_SUPPLY_NATIVE_TOKEN", data: bytes("")});
        extension.execute{value: supplyAmount}(actions);

        uint256 poolWethAfter = IERC20(WETH).balanceOf(address(ib));
        uint256 user1EthAfter = user1.balance;
        assertEq(poolWethAfter - poolWethBefore, supplyAmount);
        assertEq(user1EthBefore - user1EthAfter, supplyAmount);
    }

    function testBorrowEther() public {
        prepareBorrow();

        uint256 poolWethBefore = IERC20(WETH).balanceOf(address(ib));
        uint256 user1EthBefore = user1.balance;
        uint256 borrowAmount = 10e18;

        vm.prank(user1);
        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_BORROW_NATIVE_TOKEN", data: abi.encode(borrowAmount)});
        extension.execute(actions);

        uint256 poolWethAfter = IERC20(WETH).balanceOf(address(ib));
        uint256 user1EthAfter = user1.balance;
        assertEq(poolWethBefore - poolWethAfter, borrowAmount);
        assertEq(user1EthAfter - user1EthBefore, borrowAmount);
    }

    function testRedeemEther() public {
        uint256 supplyAmount = 10e18;

        vm.prank(user1);
        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_SUPPLY_NATIVE_TOKEN", data: bytes("")});
        extension.execute{value: supplyAmount}(actions);

        uint256 poolWethBefore = IERC20(WETH).balanceOf(address(ib));
        uint256 user1EthBefore = user1.balance;

        uint256 redeemAmount = 5e18;

        vm.prank(user1);
        actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_REDEEM_NATIVE_TOKEN", data: abi.encode(redeemAmount)});
        extension.execute(actions);

        uint256 poolWethAfter = IERC20(WETH).balanceOf(address(ib));
        uint256 user1EthAfter = user1.balance;
        assertEq(poolWethBefore - poolWethAfter, redeemAmount);
        assertEq(user1EthAfter - user1EthBefore, redeemAmount);
    }

    function testRedeemEtherFull() public {
        uint256 supplyAmount = 10e18;

        vm.prank(user1);
        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_SUPPLY_NATIVE_TOKEN", data: bytes("")});
        extension.execute{value: supplyAmount}(actions);

        uint256 poolWethBefore = IERC20(WETH).balanceOf(address(ib));
        uint256 user1EthBefore = user1.balance;

        uint256 redeemAmount = type(uint256).max;

        vm.prank(user1);
        actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_REDEEM_NATIVE_TOKEN", data: abi.encode(redeemAmount)});
        extension.execute(actions);

        uint256 poolWethAfter = IERC20(WETH).balanceOf(address(ib));
        uint256 user1EthAfter = user1.balance;
        assertEq(poolWethBefore - poolWethAfter, 10e18);
        assertEq(user1EthAfter - user1EthBefore, 10e18);
    }

    function testRepayEther() public {
        prepareBorrow();

        uint256 borrowAmount = 10e18;

        vm.prank(user1);
        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_BORROW_NATIVE_TOKEN", data: abi.encode(borrowAmount)});
        extension.execute(actions);

        uint256 poolWethBefore = IERC20(WETH).balanceOf(address(ib));
        uint256 user1EthBefore = user1.balance;

        uint256 repayAmount = 5e18;

        vm.prank(user1);
        actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_REPAY_NATIVE_TOKEN", data: bytes("")});
        extension.execute{value: repayAmount}(actions);

        uint256 poolWethAfter = IERC20(WETH).balanceOf(address(ib));
        uint256 user1EthAfter = user1.balance;
        assertEq(poolWethAfter - poolWethBefore, repayAmount);
        assertEq(user1EthBefore - user1EthAfter, repayAmount);
    }

    function testRepayEtherFull() public {
        prepareBorrow();

        uint256 borrowAmount = 10e18;

        vm.prank(user1);
        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_BORROW_NATIVE_TOKEN", data: abi.encode(borrowAmount)});
        extension.execute(actions);

        uint256 poolWethBefore = IERC20(WETH).balanceOf(address(ib));
        uint256 user1EthBefore = user1.balance;

        uint256 repayAmount = 12e18; // more than borrowed

        vm.prank(user1);
        actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_REPAY_NATIVE_TOKEN", data: bytes("")});
        extension.execute{value: repayAmount}(actions);

        uint256 poolWethAfter = IERC20(WETH).balanceOf(address(ib));
        uint256 user1EthAfter = user1.balance;
        assertEq(poolWethAfter - poolWethBefore, 10e18);
        assertEq(user1EthBefore - user1EthAfter, 10e18);
    }

    function testSupplyBorrowRedeemRepay() public {
        /**
         * Supply 10,000 DAI to borrow 5,000 USDT and repay and redeem full.
         */
        uint256 supplyAmount = 10000e18;
        uint256 borrowAmount = 5000e6;

        deal(DAI, user1, supplyAmount);

        uint256 userUsdtBefore = IERC20(USDT).balanceOf(user1);
        uint256 userDaiBefore = IERC20(DAI).balanceOf(user1);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(ib), supplyAmount); // Approve Iron Bank.
        TxBuilderExtension.Action[] memory actions1 = new TxBuilderExtension.Action[](2);
        actions1[0] = TxBuilderExtension.Action({name: "ACTION_SUPPLY", data: abi.encode(DAI, supplyAmount)});
        actions1[1] = TxBuilderExtension.Action({name: "ACTION_BORROW", data: abi.encode(USDT, borrowAmount)});
        extension.execute(actions1);

        uint256 userUsdtAfter = IERC20(USDT).balanceOf(user1);
        uint256 userDaiAfter = IERC20(DAI).balanceOf(user1);

        assertEq(userUsdtAfter - userUsdtBefore, borrowAmount);
        assertEq(userDaiBefore - userDaiAfter, supplyAmount);

        IERC20(USDT).safeIncreaseAllowance(address(ib), borrowAmount); // Approve Iron Bank.
        TxBuilderExtension.Action[] memory actions2 = new TxBuilderExtension.Action[](2);
        actions2[0] = TxBuilderExtension.Action({name: "ACTION_REPAY", data: abi.encode(USDT, type(uint256).max)});
        actions2[1] = TxBuilderExtension.Action({name: "ACTION_REDEEM", data: abi.encode(DAI, type(uint256).max)});
        extension.execute(actions2);

        assertEq(ib.getBorrowBalance(user1, USDT), 0);
        assertEq(ib.getSupplyBalance(user1, DAI), 0);

        vm.stopPrank();
    }

    function testSupplyStEth() public {
        uint256 poolWStEthBefore = IERC20(WSTETH).balanceOf(address(ib));
        uint256 supplyAmount = 10e18;
        uint256 wstEthSupplyAmount = WstEthInterface(WSTETH).getWstETHByStETH(supplyAmount);

        vm.startPrank(user1);
        IERC20(STETH).safeIncreaseAllowance(address(extension), type(uint256).max); // Approve extension.

        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_SUPPLY_STETH", data: abi.encode(supplyAmount)});
        extension.execute(actions);
        vm.stopPrank();

        uint256 poolWStEthAfter = IERC20(WSTETH).balanceOf(address(ib));
        assertEq(poolWStEthAfter - poolWStEthBefore, wstEthSupplyAmount);
    }

    function testBorrowStEth() public {
        prepareBorrow();

        uint256 poolWStEthBefore = IERC20(WSTETH).balanceOf(address(ib));
        uint256 borrowAmount = 10e18;
        uint256 wstEthBorrowAmount = WstEthInterface(WSTETH).getWstETHByStETH(borrowAmount);

        vm.prank(user1);
        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_BORROW_STETH", data: abi.encode(borrowAmount)});
        extension.execute(actions);

        uint256 poolWStEthAfter = IERC20(WSTETH).balanceOf(address(ib));
        assertEq(poolWStEthBefore - poolWStEthAfter, wstEthBorrowAmount);
    }

    function testRedeemStEth() public {
        uint256 supplyAmount = 10e18;

        vm.startPrank(user1);
        IERC20(STETH).safeIncreaseAllowance(address(extension), type(uint256).max); // Approve extension.

        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_SUPPLY_STETH", data: abi.encode(supplyAmount)});
        extension.execute(actions);

        uint256 poolWStEthBefore = IERC20(WSTETH).balanceOf(address(ib));
        uint256 redeemAmount = 5e18;
        uint256 wstEthRedeemAmount = WstEthInterface(WSTETH).getWstETHByStETH(redeemAmount);

        actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_REDEEM_STETH", data: abi.encode(redeemAmount)});
        extension.execute(actions);

        uint256 poolWStEthAfter = IERC20(WSTETH).balanceOf(address(ib));
        assertEq(poolWStEthBefore - poolWStEthAfter, wstEthRedeemAmount);
        vm.stopPrank();
    }

    function testRedeemStEthFull() public {
        uint256 supplyAmount = 10e18;

        vm.startPrank(user1);
        IERC20(STETH).safeIncreaseAllowance(address(extension), type(uint256).max); // Approve extension.

        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_SUPPLY_STETH", data: abi.encode(supplyAmount)});
        extension.execute(actions);

        uint256 poolWStEthBefore = IERC20(WSTETH).balanceOf(address(ib));
        uint256 wstEthRedeemAmount = WstEthInterface(WSTETH).getWstETHByStETH(supplyAmount);
        uint256 redeemAmount = type(uint256).max;

        actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_REDEEM_STETH", data: abi.encode(redeemAmount)});
        extension.execute(actions);

        uint256 poolWStEthAfter = IERC20(WSTETH).balanceOf(address(ib));
        assertEq(poolWStEthBefore - poolWStEthAfter, wstEthRedeemAmount);
        assertEq(ib.getSupplyBalance(user1, WSTETH), 0);
        vm.stopPrank();
    }

    function testRepayStEth() public {
        prepareBorrow();

        uint256 borrowAmount = 10e18;

        vm.startPrank(user1);
        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_BORROW_STETH", data: abi.encode(borrowAmount)});
        extension.execute(actions);

        uint256 poolWStEthBefore = IERC20(WSTETH).balanceOf(address(ib));
        uint256 repayAmount = 5e18;
        uint256 wstEthRepayAmount = WstEthInterface(WSTETH).getWstETHByStETH(repayAmount);

        IERC20(STETH).safeIncreaseAllowance(address(extension), type(uint256).max); // Approve extension.

        actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_REPAY_STETH", data: abi.encode(repayAmount)});
        extension.execute(actions);

        uint256 poolWStEthAfter = IERC20(WSTETH).balanceOf(address(ib));
        assertEq(poolWStEthAfter - poolWStEthBefore, wstEthRepayAmount);
        vm.stopPrank();
    }

    function testRepayStEthFull() public {
        prepareBorrow();

        uint256 borrowAmount = 10e18;

        vm.startPrank(user1);
        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_BORROW_STETH", data: abi.encode(borrowAmount)});
        extension.execute(actions);

        uint256 poolWStEthBefore = IERC20(WSTETH).balanceOf(address(ib));
        uint256 wstEthRepayAmount = WstEthInterface(WSTETH).getWstETHByStETH(borrowAmount);
        uint256 repayAmount = type(uint256).max;

        IERC20(STETH).safeIncreaseAllowance(address(extension), type(uint256).max); // Approve extension.

        actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_REPAY_STETH", data: abi.encode(repayAmount)});
        extension.execute(actions);

        uint256 poolWStEthAfter = IERC20(WSTETH).balanceOf(address(ib));
        assertEq(poolWStEthAfter - poolWStEthBefore, wstEthRepayAmount);
        assertEq(ib.getBorrowBalance(user1, WSTETH), 0);
        vm.stopPrank();
    }

    function testSupplyPToken() public {
        uint256 supplyAmount = 10000e18;

        // User1 needs to have DAI to supply to pDAI.
        deal(DAI, user1, supplyAmount);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(extension), type(uint256).max); // Approve extension.

        uint256 poolPDaiBefore = IERC20(pDAI).balanceOf(address(ib));
        uint256 user1DaiBefore = IERC20(DAI).balanceOf(user1);

        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](1);
        actions[0] =
            TxBuilderExtension.Action({name: "ACTION_SUPPLY_PTOKEN", data: abi.encode(address(pDAI), supplyAmount)});
        extension.execute(actions);

        uint256 poolPDaiAfter = IERC20(pDAI).balanceOf(address(ib));
        uint256 user1DaiAfter = IERC20(DAI).balanceOf(user1);
        assertEq(poolPDaiAfter - poolPDaiBefore, supplyAmount);
        assertEq(user1DaiBefore - user1DaiAfter, supplyAmount);
        vm.stopPrank();
    }

    function testRedeemPToken() public {
        uint256 supplyAmount = 10000e18;

        // User1 needs to have DAI to supply to pDAI.
        deal(DAI, user1, supplyAmount);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(extension), type(uint256).max); // Approve extension.

        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](1);
        actions[0] =
            TxBuilderExtension.Action({name: "ACTION_SUPPLY_PTOKEN", data: abi.encode(address(pDAI), supplyAmount)});
        extension.execute(actions);

        uint256 poolPDaiBefore = IERC20(pDAI).balanceOf(address(ib));
        uint256 user1DaiBefore = IERC20(DAI).balanceOf(user1);
        uint256 redeemAmount = 5000e18;

        actions = new TxBuilderExtension.Action[](1);
        actions[0] =
            TxBuilderExtension.Action({name: "ACTION_REDEEM_PTOKEN", data: abi.encode(address(pDAI), redeemAmount)});
        extension.execute(actions);

        uint256 poolPDaiAfter = IERC20(pDAI).balanceOf(address(ib));
        uint256 user1DaiAfter = IERC20(DAI).balanceOf(user1);
        assertEq(poolPDaiBefore - poolPDaiAfter, redeemAmount);
        assertEq(user1DaiAfter - user1DaiBefore, redeemAmount);
        vm.stopPrank();
    }

    function testRedeemPTokenFull() public {
        uint256 supplyAmount = 10000e18;

        // User1 needs to have DAI to supply to pDAI.
        deal(DAI, user1, supplyAmount);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(extension), type(uint256).max); // Approve extension.

        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](1);
        actions[0] =
            TxBuilderExtension.Action({name: "ACTION_SUPPLY_PTOKEN", data: abi.encode(address(pDAI), supplyAmount)});
        extension.execute(actions);

        uint256 poolPDaiBefore = IERC20(pDAI).balanceOf(address(ib));
        uint256 user1DaiBefore = IERC20(DAI).balanceOf(user1);
        uint256 redeemAmount = type(uint256).max;

        actions = new TxBuilderExtension.Action[](1);
        actions[0] =
            TxBuilderExtension.Action({name: "ACTION_REDEEM_PTOKEN", data: abi.encode(address(pDAI), redeemAmount)});
        extension.execute(actions);

        uint256 poolPDaiAfter = IERC20(pDAI).balanceOf(address(ib));
        uint256 user1DaiAfter = IERC20(DAI).balanceOf(user1);
        assertEq(poolPDaiBefore - poolPDaiAfter, 10000e18);
        assertEq(user1DaiAfter - user1DaiBefore, 10000e18);
        vm.stopPrank();
    }

    function testDeferLiquidityCheckOnly() public {
        // Nothing will happen.
        vm.prank(user1);
        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_DEFER_LIQUIDITY_CHECK", data: bytes("")});
        extension.execute(actions);
    }

    function testDeferLiquidityCheckWithPToken() public {
        uint256 supplyAmount = 10000e18;
        uint256 borrowAmount = 5000e6; // USDT

        // Give user1 some DAI.
        deal(DAI, user1, supplyAmount);

        // User1 supplies DAI and borrows USDT.
        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(ib), supplyAmount);
        ib.supply(user1, user1, DAI, supplyAmount);
        ib.borrow(user1, user1, USDT, borrowAmount);

        IERC20(DAI).safeIncreaseAllowance(address(extension), type(uint256).max); // Approve extension.

        // Convert DAI to pDAI.
        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](3);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_DEFER_LIQUIDITY_CHECK", data: bytes("")});
        actions[1] = TxBuilderExtension.Action({name: "ACTION_REDEEM", data: abi.encode(DAI, supplyAmount)});
        actions[2] =
            TxBuilderExtension.Action({name: "ACTION_SUPPLY_PTOKEN", data: abi.encode(address(pDAI), supplyAmount)});
        extension.execute(actions);
        vm.stopPrank();

        assertEq(ib.getSupplyBalance(user1, DAI), 0);
        assertEq(ib.getSupplyBalance(user1, address(pDAI)), supplyAmount);
    }

    function testDeferLiquidityCheckWithSupplyBorrow() public {
        uint256 supplyAmount = 100000e18;
        uint256 borrowAmount1 = 5000e6; // USDT
        uint256 borrowAmount2 = 10e18; // WETH
        uint256 borrowAmount3 = 5e18; // WSTETH

        // Give user1 some DAI.
        deal(DAI, user1, supplyAmount);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(ib), supplyAmount);

        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](5);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_DEFER_LIQUIDITY_CHECK", data: bytes("")}); // Defer liquidity check first and then supply.
        actions[1] = TxBuilderExtension.Action({name: "ACTION_SUPPLY", data: abi.encode(DAI, supplyAmount)});
        actions[2] = TxBuilderExtension.Action({name: "ACTION_BORROW", data: abi.encode(USDT, borrowAmount1)});
        actions[3] = TxBuilderExtension.Action({name: "ACTION_BORROW", data: abi.encode(WETH, borrowAmount2)});
        actions[4] = TxBuilderExtension.Action({name: "ACTION_BORROW", data: abi.encode(WSTETH, borrowAmount3)});
        extension.execute(actions);
        vm.stopPrank();

        assertEq(ib.getBorrowBalance(user1, USDT), borrowAmount1);
        assertEq(ib.getBorrowBalance(user1, WETH), borrowAmount2);
        assertEq(ib.getBorrowBalance(user1, WSTETH), borrowAmount3);
    }

    function testDeferLiquidityCheckWithSupplyBorrow2() public {
        uint256 supplyAmount = 100000e18;
        uint256 borrowAmount1 = 5000e6; // USDT
        uint256 borrowAmount2 = 10e18; // WETH
        uint256 borrowAmount3 = 5e18; // WSTETH

        // Give user1 some DAI.
        deal(DAI, user1, supplyAmount);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(ib), supplyAmount);

        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](5);
        actions[0] = TxBuilderExtension.Action({name: "ACTION_SUPPLY", data: abi.encode(DAI, supplyAmount)});
        actions[1] = TxBuilderExtension.Action({name: "ACTION_DEFER_LIQUIDITY_CHECK", data: bytes("")}); // Supply first and then defer liquidity check.
        actions[2] = TxBuilderExtension.Action({name: "ACTION_BORROW", data: abi.encode(USDT, borrowAmount1)});
        actions[3] = TxBuilderExtension.Action({name: "ACTION_BORROW", data: abi.encode(WETH, borrowAmount2)});
        actions[4] = TxBuilderExtension.Action({name: "ACTION_BORROW", data: abi.encode(WSTETH, borrowAmount3)});
        extension.execute(actions);
        vm.stopPrank();

        assertEq(ib.getBorrowBalance(user1, USDT), borrowAmount1);
        assertEq(ib.getBorrowBalance(user1, WETH), borrowAmount2);
        assertEq(ib.getBorrowBalance(user1, WSTETH), borrowAmount3);
    }

    function prepareBorrow() internal {
        // Make user1 have some collateral to borrow.
        deal(DAI, user1, 1000000e18);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(ib), 1000000e18);
        ib.supply(user1, user1, DAI, 1000000e18);
        vm.stopPrank();
    }
}
