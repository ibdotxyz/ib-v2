// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract BorrowTest is Test, Common {
    uint16 internal constant reserveFactor = 1000; // 10%

    int256 internal constant market1Price = 1500e8;
    int256 internal constant market2Price = 200e8;
    uint16 internal constant market1CollateralFactor = 8000; // 80%

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    FeedRegistry registry;
    PriceOracle oracle;

    ERC20Market market1;
    ERC20Market market2;
    DebtToken debtToken1;
    DebtToken debtToken2;

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

        TripleSlopeRateModel irm = createDefaultIRM();

        (market1,, debtToken1) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);
        (market2,, debtToken2) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);
        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.USD, market2Price);

        configureMarketAsCollateral(admin, configurator, address(market1), market1CollateralFactor);

        deal(address(market1), user1, 10000e18);
        deal(address(market2), user2, 10000e18);
    }

    function testBorrow() public {
        uint256 market1SupplyAmount = 100e18;
        uint256 market2BorrowAmount = 500e18;

        vm.startPrank(user2);
        market2.approve(address(ib), market2BorrowAmount);
        ib.supply(user2, user2, address(market2), market2BorrowAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user1, user1, address(market1), market1SupplyAmount);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Borrow(address(market2), user1, user1, market2BorrowAmount, market2BorrowAmount, market2BorrowAmount);

        ib.borrow(user1, user1, address(market2), market2BorrowAmount);
        vm.stopPrank();

        assertEq(market2.balanceOf(user1), market2BorrowAmount);
        assertEq(ib.getBorrowBalance(user1, address(market2)), market2BorrowAmount);
        assertEq(debtToken2.balanceOf(user1), market2BorrowAmount);

        address[] memory userEnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(userEnteredMarkets.length, 2);
        assertEq(userEnteredMarkets[0], address(market1));
        assertEq(userEnteredMarkets[1], address(market2));

        /**
         * collateral value = 100 * 0.8 * 1500 = 120,000
         * borrowed value = 500 * 200 = 100,000
         */
        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 120_000e18);
        assertEq(debtValue, 100_000e18);
    }

    function testBorrowToOther() public {
        uint256 market1SupplyAmount = 100e18;
        uint256 market2BorrowAmount = 500e18;

        vm.startPrank(user2);
        market2.approve(address(ib), market2BorrowAmount);
        ib.supply(user2, user2, address(market2), market2BorrowAmount);
        vm.stopPrank();

        uint256 user2Market2BalanceBefore = market2.balanceOf(user2);

        vm.startPrank(user1);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user1, user1, address(market1), market1SupplyAmount);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Borrow(address(market2), user1, user2, market2BorrowAmount, market2BorrowAmount, market2BorrowAmount);

        ib.borrow(user1, user2, address(market2), market2BorrowAmount);
        vm.stopPrank();

        uint256 user2Market2BalanceAfter = market2.balanceOf(user2);

        assertEq(market2.balanceOf(user1), 0);
        assertEq(user2Market2BalanceAfter - user2Market2BalanceBefore, market2BorrowAmount);
        assertEq(ib.getBorrowBalance(user1, address(market2)), market2BorrowAmount);
        assertEq(debtToken2.balanceOf(user1), market2BorrowAmount);

        address[] memory userEnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(userEnteredMarkets.length, 2);
        assertEq(userEnteredMarkets[0], address(market1));
        assertEq(userEnteredMarkets[1], address(market2));

        /**
         * collateral value = 100 * 0.8 * 1500 = 120,000
         * borrowed value = 500 * 200 = 100,000
         */
        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 120_000e18);
        assertEq(debtValue, 100_000e18);
    }

    function testBorrowOnBehalf() public {
        uint256 market1SupplyAmount = 100e18;
        uint256 market2BorrowAmount = 500e18;

        vm.startPrank(user2);
        market2.approve(address(ib), market2BorrowAmount);
        ib.supply(user2, user2, address(market2), market2BorrowAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user1, user1, address(market1), market1SupplyAmount);
        ib.setUserExtension(user2, true);
        vm.stopPrank();

        vm.prank(user2);
        vm.expectEmit(true, true, true, true, address(ib));
        emit Borrow(address(market2), user1, user1, market2BorrowAmount, market2BorrowAmount, market2BorrowAmount);

        ib.borrow(user1, user1, address(market2), market2BorrowAmount);

        assertEq(market2.balanceOf(user1), market2BorrowAmount);
        assertEq(ib.getBorrowBalance(user1, address(market2)), market2BorrowAmount);
        assertEq(debtToken2.balanceOf(user1), market2BorrowAmount);

        address[] memory userEnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(userEnteredMarkets.length, 2);
        assertEq(userEnteredMarkets[0], address(market1));
        assertEq(userEnteredMarkets[1], address(market2));

        /**
         * collateral value = 100 * 0.8 * 1500 = 120,000
         * borrowed value = 500 * 200 = 100,000
         */
        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 120_000e18);
        assertEq(debtValue, 100_000e18);
    }

    function testBorrowWithInterests() public {
        uint256 market1SupplyAmount = 100e18;
        uint256 market2BorrowAmount = 300e18;
        uint256 market2SupplyAmount = 500e18;

        vm.startPrank(user2);
        market2.approve(address(ib), market2SupplyAmount);
        ib.supply(user2, user2, address(market2), market2SupplyAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user1, user1, address(market1), market1SupplyAmount);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Borrow(address(market2), user1, user1, market2BorrowAmount, market2BorrowAmount, market2BorrowAmount);

        ib.borrow(user1, user1, address(market2), market2BorrowAmount);
        vm.stopPrank();

        assertEq(ib.getBorrowBalance(user1, address(market2)), market2BorrowAmount);
        assertEq(debtToken2.balanceOf(user1), market2BorrowAmount);

        address[] memory userEnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(userEnteredMarkets.length, 2);
        assertEq(userEnteredMarkets[0], address(market1));
        assertEq(userEnteredMarkets[1], address(market2));

        fastForwardTime(86400);
        ib.accrueInterest(address(market2));

        /**
         * utilization = 300 / 500 = 60% < kink1 = 80%
         * borrow rate = 0.000000001 + 0.6 * 0.000000001 = 0.0000000016
         * borrow interest = 0.0000000016 * 86400 * 300 = 0.041472
         */
        uint256 interests = 0.041472e18;

        assertEq(ib.getBorrowBalance(user1, address(market2)), market2BorrowAmount + interests);
        assertEq(debtToken2.balanceOf(user1), market2BorrowAmount + interests);
    }

    function testBorrowWithCreditLimit() public {
        uint256 borrowAmount = 500e18;

        vm.startPrank(user2);
        market2.approve(address(ib), borrowAmount);
        ib.supply(user2, user2, address(market2), borrowAmount);
        vm.stopPrank();

        vm.prank(admin);
        creditLimitManager.setCreditLimit(user1, address(market2), borrowAmount);

        vm.prank(user1);
        vm.expectEmit(true, true, true, true, address(ib));
        emit Borrow(address(market2), user1, user1, borrowAmount, borrowAmount, borrowAmount);

        ib.borrow(user1, user1, address(market2), borrowAmount);

        uint256 userBorrowBalance = ib.getBorrowBalance(user1, address(market2));
        assertEq(userBorrowBalance, borrowAmount);

        address[] memory userEnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(userEnteredMarkets.length, 1);
        assertEq(userEnteredMarkets[0], address(market2));

        /**
         * collateral value = 0
         * borrowed value = 500 * 200 = 100,000
         */
        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 0);
        assertEq(debtValue, 100_000e18);
    }

    function testCannotBorrowForUnauthorized() public {
        uint256 borrowAmount = 500e18;

        vm.prank(user1);
        vm.expectRevert("!authorized");
        ib.borrow(user2, user2, address(market2), borrowAmount);
    }

    function testCannotBorrowForMarketNotListed() public {
        ERC20 invalidMarket = new ERC20("Token", "TOKEN");

        uint256 borrowAmount = 500e18;

        vm.prank(user1);
        vm.expectRevert("not listed");
        ib.borrow(user1, user1, address(invalidMarket), borrowAmount);
    }

    function testCannotBorrowForMarketBorrowPaused() public {
        uint256 borrowAmount = 500e18;

        vm.prank(admin);
        configurator.setMarketBorrowPaused(address(market2), true);

        vm.prank(user1);
        vm.expectRevert("borrow paused");
        ib.borrow(user1, user1, address(market2), borrowAmount);
    }

    function testCannotBorrowForInsufficientCash() public {
        uint256 borrowAmount = 500e18;

        vm.startPrank(user2);
        market2.approve(address(ib), borrowAmount);
        ib.supply(user2, user2, address(market2), borrowAmount);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert("insufficient cash");
        ib.borrow(user1, user1, address(market2), borrowAmount + 1);
    }

    function testCannotBorrowForBorrowCapReached() public {
        uint256 borrowAmount = 500e18;
        uint256 borrowCap = 499e18;

        vm.startPrank(user2);
        market2.approve(address(ib), borrowAmount);
        ib.supply(user2, user2, address(market2), borrowAmount);
        vm.stopPrank();

        vm.prank(admin);
        configurator.setMarketBorrowCaps(constructMarketCapArgument(address(market2), borrowCap));

        vm.prank(user1);
        vm.expectRevert("borrow cap reached");
        ib.borrow(user1, user1, address(market2), borrowAmount);
    }

    function testCannotBorrowForBorrowCapReached2() public {
        uint256 borrowCap = 500e18;
        uint256 borrowAmount = borrowCap - 1; // borrow almost to cap

        vm.prank(admin);
        configurator.setMarketBorrowCaps(constructMarketCapArgument(address(market2), borrowCap));

        vm.startPrank(user2);
        market2.approve(address(ib), 500e18);
        ib.supply(user2, user2, address(market2), 500e18);
        vm.stopPrank();

        vm.startPrank(user1);
        market1.approve(address(ib), 100e18);
        ib.supply(user1, user1, address(market1), 100e18);
        ib.borrow(user1, user1, address(market2), borrowAmount);
        vm.stopPrank();

        fastForwardTime(86400);

        // The total borrow is now greater than the borrw cap due to the borrow interest.
        vm.prank(user1);
        vm.expectRevert("borrow cap reached");
        ib.borrow(user1, user1, address(market2), 1);
    }

    function testCannotBorrowForCreditAccountBorrowToOthers() public {
        uint256 borrowAmount = 500e18;

        vm.startPrank(user2);
        market2.approve(address(ib), borrowAmount);
        ib.supply(user2, user2, address(market2), borrowAmount);
        vm.stopPrank();

        vm.prank(admin);
        creditLimitManager.setCreditLimit(user1, address(market2), borrowAmount);

        vm.prank(user1);
        vm.expectRevert("credit account can only borrow to itself");
        ib.borrow(user1, user2, address(market2), borrowAmount);
    }

    function testCannotBorrowForInsufficientCreditLimit() public {
        uint256 borrowAmount = 500e18;

        vm.startPrank(user2);
        market2.approve(address(ib), borrowAmount);
        ib.supply(user2, user2, address(market2), borrowAmount);
        vm.stopPrank();

        vm.prank(admin);
        creditLimitManager.setCreditLimit(user1, address(market2), borrowAmount - 1);

        vm.prank(user1);
        vm.expectRevert("insufficient credit limit");
        ib.borrow(user1, user1, address(market2), borrowAmount);
    }

    function testCannotBorrowForInsufficientCollateral() public {
        /**
         * collateral value = 100 * 0.8 * 1500 = 120,000
         * borrowed value = 601 * 200 = 120,200
         */
        uint256 market1SupplyAmount = 100e18;
        uint256 market2BorrowAmount = 601e18;

        vm.startPrank(user2);
        market2.approve(address(ib), market2BorrowAmount);
        ib.supply(user2, user2, address(market2), market2BorrowAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user1, user1, address(market1), market1SupplyAmount);
        vm.expectRevert("insufficient collateral");
        ib.borrow(user1, user1, address(market2), market2BorrowAmount);
        vm.stopPrank();
    }
}
