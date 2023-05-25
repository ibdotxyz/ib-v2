// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract LiquidateTest is Test, Common {
    uint16 internal constant reserveFactor = 1000; // 10%
    int256 internal constant market1Price = 1500e8;
    int256 internal constant market2Price = 200e8;
    uint16 internal constant market1CollateralFactor = 8000; // 80%
    uint16 internal constant market1LiquidationThreshold = 9000; // 90%
    uint16 internal constant market1LiquidationBonus = 11000; // 110%

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    TripleSlopeRateModel irm;
    FeedRegistry registry;
    PriceOracle oracle;

    ERC20Market market1;
    ERC20Market market2;

    address admin = address(64);
    address user1 = address(128);
    address user2 = address(256);

    function setUp() public {
        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);

        vm.prank(admin);
        ib.setMarketConfigurator(address(configurator));

        creditLimitManager = createCreditLimitManager(admin, ib);

        vm.prank(admin);
        ib.setCreditLimitManager(address(creditLimitManager));

        irm = createDefaultIRM();

        (market1,,) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);
        (market2,,) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);
        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.USD, market2Price);

        deal(address(market1), user1, 10000e18);
        deal(address(market2), user2, 10000e18);

        vm.startPrank(admin);
        configurator.configureMarketAsCollateral(
            address(market1), market1CollateralFactor, market1LiquidationThreshold, market1LiquidationBonus
        );

        // Injest some liquidity for borrow.
        market2.approve(address(ib), type(uint256).max);
        ib.supply(admin, admin, address(market2), 10_000e18);
        vm.stopPrank();

        uint256 market1SupplyAmount = 100e18;
        uint256 market2BorrowAmount = 500e18;

        vm.startPrank(user1);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user1, user1, address(market1), market1SupplyAmount);
        ib.borrow(user1, user1, address(market2), market2BorrowAmount);
        vm.stopPrank();
    }

    function testLiquidation() public {
        /**
         * collateral value = 100 * 0.8 * 1500 = 120,000
         * liquidation collateral value = 100 * 0.9 * 1500 = 135,000
         * borrowed value = 500 * 200 = 100,000
         */
        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 120_000e18);
        assertEq(debtValue, 100_000e18);
        assertFalse(ib.isUserLiquidatable(user1));

        int256 newMarket1Price = 1200e8;
        setPriceToRegistry(registry, admin, address(market1), Denominations.USD, newMarket1Price);

        /**
         * collateral value = 100 * 0.8 * 1200 = 96,000
         * liquidation collateral value = 100 * 0.9 * 1200 = 108,000
         * borrowed value = 500 * 200 = 100,000
         */
        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 96_000e18);
        assertEq(debtValue, 100_000e18);
        assertFalse(ib.isUserLiquidatable(user1));

        // Cannot borrow more but still not liquidatable.
        vm.prank(user1);
        vm.expectRevert("insufficient collateral");
        ib.borrow(user1, user1, address(market2), 1); // Even 1 wei is not allowed to borrow.

        newMarket1Price = 1100e8;
        setPriceToRegistry(registry, admin, address(market1), Denominations.USD, newMarket1Price);

        /**
         * collateral value = 100 * 0.8 * 1100 = 88,000
         * liquidation collateral value = 100 * 0.9 * 1100 = 99,000
         * borrowed value = 500 * 200 = 100,000
         */
        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 88_000e18);
        assertEq(debtValue, 100_000e18);
        assertTrue(ib.isUserLiquidatable(user1));

        // User2 liquidates user1.
        uint256 repayAmount = 100e18;

        vm.startPrank(user2);
        market2.approve(address(ib), repayAmount);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Liquidate(user2, user1, address(market2), address(market1), repayAmount, 20e18);

        ib.liquidate(user2, user1, address(market2), address(market1), repayAmount);

        ib.redeem(user2, user2, address(market1), type(uint256).max);
        vm.stopPrank();

        /**
         * debt repaid = 100 * 200 = 20,000
         * collateral received (with 110% bonus) = 20,000 / 1100 * 1.1 = 20
         */
        uint256 user2Market1Balance = market1.balanceOf(user2);
        assertEq(user2Market1Balance, 20e18);

        /**
         * collateral value = 80 * 0.8 * 1100 = 70,400
         * liquidation collateral value = 80 * 0.9 * 1100 = 79,200
         * borrowed value = 400 * 200 = 80,000
         */
        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 70_400e18);
        assertEq(debtValue, 80_000e18);
        assertTrue(ib.isUserLiquidatable(user1));

        // User2 liquidates user1 again.
        repayAmount = type(uint256).max;

        vm.startPrank(user2);
        market2.approve(address(ib), repayAmount);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Liquidate(user2, user1, address(market2), address(market1), 400e18, 80e18);

        ib.liquidate(user2, user1, address(market2), address(market1), repayAmount);

        ib.redeem(user2, user2, address(market1), type(uint256).max);
        vm.stopPrank();

        /**
         * debt repaid = 500 * 200 = 100,000
         * collateral received (with 110% bonus) = 100,000 / 1100 * 1.1 = 100
         */
        user2Market1Balance = market1.balanceOf(user2);
        assertEq(user2Market1Balance, 100e18);

        /**
         * collateral value = 0
         * liquidation collateral value = 0
         * borrowed value = 0
         */
        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 0);
        assertEq(debtValue, 0);
        assertFalse(ib.isUserLiquidatable(user1));

        // 10,000 - 500 = 9,500
        uint256 user2Market2Balance = market2.balanceOf(user2);
        assertEq(user2Market2Balance, 9500e18);
    }

    function testLiquidation2() public {
        // Price drops drastically.
        int256 newMarket1Price = 1000e8;
        setPriceToRegistry(registry, admin, address(market1), Denominations.USD, newMarket1Price);

        /**
         * collateral value = 100 * 0.8 * 1000 = 80,000
         * liquidation collateral value = 100 * 0.9 * 1000 = 90,000
         * borrowed value = 500 * 200 = 100,000
         */
        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 80_000e18);
        assertEq(debtValue, 100_000e18);
        assertTrue(ib.isUserLiquidatable(user1));

        // User2 liquidates user1.
        uint256 repayAmount = 450e18;

        vm.startPrank(user2);
        market2.approve(address(ib), repayAmount);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Liquidate(user2, user1, address(market2), address(market1), repayAmount, 99e18);

        ib.liquidate(user2, user1, address(market2), address(market1), repayAmount);

        ib.redeem(user2, user2, address(market1), type(uint256).max);
        vm.stopPrank();

        /**
         * debt repaid = 450 * 200 = 90,000
         * collateral received (with 110% bonus) = 90,000 / 1000 * 1.1 = 99
         */
        uint256 user2Market1Balance = market1.balanceOf(user2);
        assertEq(user2Market1Balance, 99e18);

        /**
         * collateral value = 1 * 0.8 * 1000 = 800
         * liquidation collateral value = 1 * 0.9 * 1000 = 900
         * borrowed value = 50 * 200 = 10,000
         */
        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 800e18);
        assertEq(debtValue, 10_000e18);

        // User1 is still liquidable but the incentive is not enough for liquidator.
        // Not liquidating in time leads to the bad debt.
        assertTrue(ib.isUserLiquidatable(user1));

        // 10,000 - 450 = 9,500
        uint256 user2Market2Balance = market2.balanceOf(user2);
        assertEq(user2Market2Balance, 9550e18);
    }

    function testLiquidation3() public {
        uint16 newMarket1LiquidationThreshold = 8000; // 80%

        vm.prank(admin);
        configurator.adjustMarketLiquidationThreshold(address(market1), newMarket1LiquidationThreshold);

        int256 newMarket2Price = 250e8;
        setPriceToRegistry(registry, admin, address(market2), Denominations.USD, newMarket2Price);

        /**
         * collateral value = 100 * 0.8 * 1500 = 120,000
         * liquidation collateral value = 100 * 0.8 * 1500 = 120,000
         * borrowed value = 500 * 250 = 125,000
         */
        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 120_000e18);
        assertEq(debtValue, 125_000e18);
        assertTrue(ib.isUserLiquidatable(user1));

        // User2 liquidates user1.
        uint256 repayAmount = 300e18;

        vm.startPrank(user2);
        market2.approve(address(ib), repayAmount);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Liquidate(user2, user1, address(market2), address(market1), repayAmount, 55e18);

        ib.liquidate(user2, user1, address(market2), address(market1), repayAmount);

        ib.redeem(user2, user2, address(market1), type(uint256).max);
        vm.stopPrank();

        /**
         * debt repaid = 300 * 250 = 75,000
         * collateral received (with 110% bonus) = 75,000 / 1500 * 1.1 = 55
         */
        uint256 user2Market1Balance = market1.balanceOf(user2);
        assertEq(user2Market1Balance, 55e18);

        /**
         * collateral value = 45 * 0.8 * 1500 = 54,000
         * liquidation collateral value = 45 * 0.8 * 1500 = 54,000
         * borrowed value = 200 * 250 = 50,000
         */
        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 54_000e18);
        assertEq(debtValue, 50_000e18);

        // User1 becomes not liquidable.
        assertFalse(ib.isUserLiquidatable(user1));
    }

    function testLiquidation4() public {
        (ERC20Market market3,,) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);

        int256 market3Price = 800e8;
        setPriceForMarket(oracle, registry, admin, address(market3), address(market3), Denominations.USD, market3Price);

        uint16 market3CollateralFactor = 5000; // 50%
        uint16 market3LiquidationThreshold = 5000; // 50%
        uint16 market3LiquidationBonus = 11000; // 110%

        vm.prank(admin);
        configurator.configureMarketAsCollateral(
            address(market3), market3CollateralFactor, market3LiquidationThreshold, market3LiquidationBonus
        );

        vm.prank(admin);
        market3.transfer(user1, 100e18);

        vm.startPrank(user1);
        market3.approve(address(ib), 100e18);
        ib.supply(user1, user1, address(market3), 100e18);
        vm.stopPrank();

        int256 newMarket1Price = 600e8;
        setPriceToRegistry(registry, admin, address(market1), Denominations.USD, newMarket1Price);

        /**
         * collateral value = 100 * 0.8 * 600 + 100 * 0.5 * 800 = 88,000
         * liquidation collateral value = 100 * 0.9 * 600 + 100 * 0.5 * 800 = 94,000
         * borrowed value = 500 * 200 = 100,000
         */
        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 88_000e18);
        assertEq(debtValue, 100_000e18);
        assertTrue(ib.isUserLiquidatable(user1));

        // User2 liquidates user1.
        uint256 repayAmount = 200e18;

        vm.startPrank(user2);
        market2.approve(address(ib), repayAmount);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Liquidate(user2, user1, address(market2), address(market3), repayAmount, 55e18);

        ib.liquidate(user2, user1, address(market2), address(market3), repayAmount);

        ib.redeem(user2, user2, address(market3), type(uint256).max);
        vm.stopPrank();

        /**
         * debt repaid = 200 * 200 = 40,000
         * collateral received (with 110% bonus) = 40,000 / 800 * 1.1 = 55
         */
        uint256 user2Market3Balance = market3.balanceOf(user2);
        assertEq(user2Market3Balance, 55e18);

        /**
         * collateral value = 100 * 0.8 * 600 + 45 * 0.5 * 800 = 66,000
         * liquidation collateral value = 100 * 0.9 * 600 + 45 * 0.5 * 800 = 72,000
         * borrowed value = 300 * 200 = 60,000
         */
        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 66_000e18);
        assertEq(debtValue, 60_000e18);

        // User1 becomes not liquidable.
        assertFalse(ib.isUserLiquidatable(user1));
    }

    function testLiquidationWithDelisting() public {
        (ERC20Market market3,,) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);

        int256 market3Price = 800e8;
        setPriceForMarket(oracle, registry, admin, address(market3), address(market3), Denominations.USD, market3Price);

        uint16 market3CollateralFactor = 5000; // 50%
        uint16 market3LiquidationThreshold = 5000; // 50%
        uint16 market3LiquidationBonus = 11000; // 110%

        vm.prank(admin);
        configurator.configureMarketAsCollateral(
            address(market3), market3CollateralFactor, market3LiquidationThreshold, market3LiquidationBonus
        );

        vm.prank(admin);
        market3.transfer(user1, 100e18);

        vm.startPrank(user1);
        market3.approve(address(ib), 100e18);
        ib.supply(user1, user1, address(market3), 100e18);
        vm.stopPrank();

        /**
         * collateral value = 100 * 0.8 * 1500 + 100 * 0.5 * 800 = 160,000
         * liquidation collateral value = 100 * 0.9 * 1500 + 100 * 0.5 * 800 = 175,000
         * borrowed value = 500 * 200 = 100,000
         */
        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 160_000e18);
        assertEq(debtValue, 100_000e18);
        assertFalse(ib.isUserLiquidatable(user1));

        vm.startPrank(admin);
        configurator.softDelistMarket(address(market1));
        configurator.adjustMarketCollateralFactor(address(market1), 0);
        configurator.adjustMarketLiquidationThreshold(address(market1), 0);
        configurator.hardDelistMarket(address(market1));
        vm.stopPrank();

        /**
         * collateral value = 100 * 0.5 * 800 = 40,000
         * liquidation collateral value = 100 * 0.5 * 800 = 40,000
         * borrowed value = 500 * 200 = 100,000
         */
        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 40_000e18);
        assertEq(debtValue, 100_000e18);
        assertTrue(ib.isUserLiquidatable(user1));

        // User2 liquidates user1.
        uint256 repayAmount = 200e18;

        vm.startPrank(user2);
        market2.approve(address(ib), repayAmount);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Liquidate(user2, user1, address(market2), address(market3), repayAmount, 55e18);

        ib.liquidate(user2, user1, address(market2), address(market3), repayAmount);

        ib.redeem(user2, user2, address(market3), type(uint256).max);
        vm.stopPrank();

        /**
         * debt repaid = 200 * 200 = 40,000
         * collateral received (with 110% bonus) = 40,000 / 800 * 1.1 = 55
         */
        uint256 user2Market3Balance = market3.balanceOf(user2);
        assertEq(user2Market3Balance, 55e18);

        /**
         * collateral value = 45 * 0.5 * 800 = 18,000
         * liquidation collateral value = 45 * 0.5 * 800 = 18,000
         * borrowed value = 300 * 200 = 60,000
         */
        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 18_000e18);
        assertEq(debtValue, 60_000e18);

        // User1 is still liquidable.
        assertTrue(ib.isUserLiquidatable(user1));
    }

    function testCannotLiquidateForInsufficientAllowance() public {
        int256 newMarket1Price = 1100e8;
        setPriceToRegistry(registry, admin, address(market1), Denominations.USD, newMarket1Price);

        uint256 repayAmount = 100e18;

        vm.prank(user2);
        vm.expectRevert("ERC20: insufficient allowance");
        ib.liquidate(user2, user1, address(market2), address(market1), repayAmount);
    }

    function testCannotLiquidateForInsufficientBalance() public {
        int256 newMarket1Price = 1100e8;
        setPriceToRegistry(registry, admin, address(market1), Denominations.USD, newMarket1Price);

        uint256 repayAmount = 100e18;

        vm.startPrank(user2);
        // Transfer out on purpose.
        market2.transfer(user1, 10_000e18);

        market2.approve(address(ib), repayAmount);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        ib.liquidate(user2, user1, address(market2), address(market1), repayAmount);
        vm.stopPrank();
    }

    function testCannotLiquidateForUnauthorized() public {
        uint256 repayAmount = 100e18;

        vm.prank(user1);
        vm.expectRevert("!authorized");
        ib.liquidate(user2, user1, address(market2), address(market1), repayAmount);
    }

    function testCannotLiquidateForBorrowMarketNotListed() public {
        ERC20 notListedMarket = new ERC20("Token", "TOKEN");

        uint256 repayAmount = 100e18;

        vm.prank(user2);
        vm.expectRevert("borrow market not listed");
        ib.liquidate(user2, user1, address(notListedMarket), address(market1), repayAmount);
    }

    function testCannotLiquidateForCollateralMarketNotListed() public {
        ERC20 notListedMarket = new ERC20("Token", "TOKEN");

        uint256 repayAmount = 100e18;

        vm.prank(user2);
        vm.expectRevert("collateral market not listed");
        ib.liquidate(user2, user1, address(market2), address(notListedMarket), repayAmount);
    }

    function testCannotLiquidateForCollateralMarketCannotBeSeized() public {
        vm.prank(admin);
        configurator.setMarketTransferPaused(address(market1), true);

        uint256 repayAmount = 100e18;

        vm.prank(user2);
        vm.expectRevert("collateral market cannot be seized");
        ib.liquidate(user2, user1, address(market2), address(market1), repayAmount);

        int256 newMarket1Price = 1100e8;
        setPriceToRegistry(registry, admin, address(market1), Denominations.USD, newMarket1Price);

        vm.prank(admin);
        configurator.setMarketTransferPaused(address(market1), false);

        vm.startPrank(user2);
        market2.approve(address(ib), repayAmount);
        ib.liquidate(user2, user1, address(market2), address(market1), repayAmount);
        vm.stopPrank();
    }

    function testCannotLiquidateForCollateralMarketCannotBeSeized2() public {
        vm.startPrank(admin);
        configurator.adjustMarketCollateralFactor(address(market1), 0);
        configurator.adjustMarketLiquidationThreshold(address(market1), 0);
        vm.stopPrank();

        uint256 repayAmount = 100e18;

        vm.prank(user2);
        vm.expectRevert("collateral market cannot be seized");
        ib.liquidate(user2, user1, address(market2), address(market1), repayAmount);

        int256 newMarket1Price = 1100e8;
        setPriceToRegistry(registry, admin, address(market1), Denominations.USD, newMarket1Price);

        vm.prank(admin);
        configurator.adjustMarketLiquidationThreshold(address(market1), market1LiquidationThreshold);

        vm.startPrank(user2);
        market2.approve(address(ib), repayAmount);
        ib.liquidate(user2, user1, address(market2), address(market1), repayAmount);
        vm.stopPrank();
    }

    function testCannotLiquidateForCannotLiquidateCreditAccount() public {
        vm.prank(admin);
        creditLimitManager.setCreditLimit(user1, address(market1), 1); // amount not important

        uint256 repayAmount = 100e18;

        vm.prank(user2);
        vm.expectRevert("cannot liquidate credit account");
        ib.liquidate(user2, user1, address(market2), address(market1), repayAmount);
    }

    function testCannotLiquidateForCannotSelfLiquidate() public {
        uint256 repayAmount = 100e18;

        vm.prank(user2);
        vm.expectRevert("cannot self liquidate");
        ib.liquidate(user2, user2, address(market2), address(market1), repayAmount);
    }

    function testCannotLiquidateForBorrowerNotLiquidatable() public {
        uint256 repayAmount = 100e18;

        vm.prank(user2);
        vm.expectRevert("borrower not liquidatable");
        ib.liquidate(user2, user1, address(market2), address(market1), repayAmount);
    }

    function testCannotLiquidateForInvalidPrice() public {
        MockPriceOracle mockOracle = new MockPriceOracle();
        mockOracle.setPrice(address(market1), 0);

        vm.prank(admin);
        ib.setPriceOracle(address(mockOracle));

        uint256 repayAmount = 100e18;

        vm.prank(user2);
        vm.expectRevert("invalid price");
        ib.liquidate(user2, user1, address(market2), address(market1), repayAmount);
    }

    function testCannotLiquidateForSeizeTooMuch() public {
        (ERC20Market market3,,) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);

        int256 market3Price = 800e8;
        setPriceForMarket(oracle, registry, admin, address(market3), address(market3), Denominations.USD, market3Price);

        uint16 market3CollateralFactor = 5000; // 50%
        uint16 market3LiquidationThreshold = 5000; // 50%
        uint16 market3LiquidationBonus = 11000; // 110%

        vm.prank(admin);
        configurator.configureMarketAsCollateral(
            address(market3), market3CollateralFactor, market3LiquidationThreshold, market3LiquidationBonus
        );

        vm.prank(admin);
        market3.transfer(user1, 100e18);

        vm.startPrank(user1);
        market3.approve(address(ib), 100e18);
        ib.supply(user1, user1, address(market3), 100e18);
        vm.stopPrank();

        int256 newMarket1Price = 600e8;
        setPriceToRegistry(registry, admin, address(market1), Denominations.USD, newMarket1Price);

        /**
         * collateral value = 100 * 0.8 * 600 + 100 * 0.5 * 800 = 88,000
         * liquidation collateral value = 100 * 0.9 * 600 + 100 * 0.5 * 800 = 94,000
         * borrowed value = 500 * 200 = 100,000
         */
        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 88_000e18);
        assertEq(debtValue, 100_000e18);
        assertTrue(ib.isUserLiquidatable(user1));

        // User2 try to liquidate user1 for max.
        uint256 repayAmount = type(uint256).max;

        vm.startPrank(user2);
        market2.approve(address(ib), repayAmount);
        vm.expectRevert("transfer amount exceeds balance");
        ib.liquidate(user2, user1, address(market2), address(market3), repayAmount);
        vm.stopPrank();
    }

    function testCannotLiquidateForInvalidSeizeAmount() public {
        // Price drops drastically.
        int256 newMarket1Price = 1000e8;
        setPriceToRegistry(registry, admin, address(market1), Denominations.USD, newMarket1Price);

        /**
         * collateral value = 100 * 0.8 * 1000 = 80,000
         * liquidation collateral value = 100 * 0.9 * 1000 = 90,000
         * borrowed value = 500 * 200 = 100,000
         */
        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 80_000e18);
        assertEq(debtValue, 100_000e18);
        assertTrue(ib.isUserLiquidatable(user1));

        // User2 liquidates user1.
        uint256 repayAmount = 0;

        vm.startPrank(user2);
        market2.approve(address(ib), repayAmount);

        vm.expectRevert("transfer zero amount");
        ib.liquidate(user2, user1, address(market2), address(market1), repayAmount);
        vm.stopPrank();
    }

    function testCalculateLiquidationOpportunity() public {
        uint256 repayAmount = 150e18;

        /**
         * debt repaid = 150 * 200 = 30,000
         * collateral received (with 110% bonus) = 30,000 / 1500 * 1.1 = 22
         */
        uint256 seizeAmount = ib.calculateLiquidationOpportunity(address(market2), address(market1), repayAmount);
        assertEq(seizeAmount, 22e18);

        repayAmount = 0;

        seizeAmount = ib.calculateLiquidationOpportunity(address(market2), address(market1), repayAmount);
        assertEq(seizeAmount, 0);
    }

    function testCannotCalculateLiquidationOpportunityForInvalidPrice() public {
        MockPriceOracle mockOracle = new MockPriceOracle();
        mockOracle.setPrice(address(market1), 100);
        mockOracle.setPrice(address(market2), 200);

        vm.prank(admin);
        ib.setPriceOracle(address(mockOracle));

        ERC20 notListedMarket = new ERC20("Token", "TOKEN");

        uint256 repayAmount = 150e18;

        vm.expectRevert("invalid price");
        ib.calculateLiquidationOpportunity(address(notListedMarket), address(market1), repayAmount);

        vm.expectRevert("invalid price");
        ib.calculateLiquidationOpportunity(address(market2), address(notListedMarket), repayAmount);

        vm.expectRevert("invalid price");
        ib.calculateLiquidationOpportunity(address(notListedMarket), address(notListedMarket), repayAmount);
    }
}
