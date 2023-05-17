// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract ExchangeRateTest is Test, Common {
    uint8 internal constant underlyingDecimals1 = 18; // 1e18
    uint8 internal constant underlyingDecimals2 = 6; // 1e6
    uint8 internal constant underlyingDecimals3 = 18; // 1e18
    uint16 internal constant reserveFactor = 1000; // 10%

    int256 internal constant market1Price = 1500e8;
    int256 internal constant market2Price = 200e8;
    int256 internal constant market3Price = 1500e8;
    uint16 internal constant market1CollateralFactor = 8000; // 80%
    uint16 internal constant market2CollateralFactor = 8000; // 80%

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    FeedRegistry registry;
    PriceOracle oracle;

    ERC20Market market1; // decimals: 18, reserve factor: 10%, price: 1500
    ERC20Market market2; // decimals: 6, reserve factor: 10%, price: 200
    ERC20Market market3; // decimals: 18, reserve factor: 0%, price: 1500
    IBToken ibToken1;
    IBToken ibToken2;
    IBToken ibToken3;

    address admin = address(64);
    address user1 = address(128);
    address reserveManager = address(256);

    function setUp() public {
        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);

        vm.prank(admin);
        ib.setMarketConfigurator(address(configurator));

        creditLimitManager = createCreditLimitManager(admin, ib);

        vm.prank(admin);
        ib.setCreditLimitManager(address(creditLimitManager));

        TripleSlopeRateModel irm = createDefaultIRM();

        (market1, ibToken1,) =
            createAndListERC20Market(underlyingDecimals1, admin, ib, configurator, irm, reserveFactor);
        (market2, ibToken2,) =
            createAndListERC20Market(underlyingDecimals2, admin, ib, configurator, irm, reserveFactor);
        (market3, ibToken3,) = createAndListERC20Market(underlyingDecimals3, admin, ib, configurator, irm, 0);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);
        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.USD, market2Price);
        setPriceForMarket(oracle, registry, admin, address(market3), address(market3), Denominations.USD, market3Price);

        configureMarketAsCollateral(admin, configurator, address(market1), market1CollateralFactor);
        configureMarketAsCollateral(admin, configurator, address(market2), market2CollateralFactor);

        deal(address(market1), user1, 10_000 * (10 ** underlyingDecimals1));
        deal(address(market2), user1, 10_000 * (10 ** underlyingDecimals2));
        deal(address(market3), user1, 10_000 * (10 ** underlyingDecimals3));

        vm.prank(admin);
        ib.setReserveManager(reserveManager);
    }

    function testExchangeRate1e6SupplyAndBorrow() public {
        // Admin provides market2 liquidity and user1 borrows market2 against market1.

        uint256 market1SupplyAmount = 100 * (10 ** underlyingDecimals1);
        uint256 market2BorrowAmount = 300 * (10 ** underlyingDecimals2);
        uint256 market2SupplyAmount = 500 * (10 ** underlyingDecimals2);

        vm.startPrank(admin);
        market2.approve(address(ib), market2SupplyAmount);
        ib.supply(admin, admin, address(market2), market2SupplyAmount);
        vm.stopPrank();

        assertEq(ib.getExchangeRate(address(market2)), 10 ** underlyingDecimals2);

        vm.startPrank(user1);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user1, user1, address(market1), market1SupplyAmount);
        ib.borrow(user1, user1, address(market2), market2BorrowAmount);
        vm.stopPrank();

        assertEq(ib.getExchangeRate(address(market2)), 10 ** underlyingDecimals2);

        fastForwardTime(86400);

        /**
         * utilization = 300 / 500 = 60% < kink1 = 80%
         * borrow rate = 0.000000001 + 0.6 * 0.000000001 = 0.0000000016
         * borrow interest = 0.0000000016 * 86400 * 300 = 0.041472
         * fee increased = 0.041472 * 0.1 = 0.004147 (truncated)
         *
         * new total borrow = 300.041472
         * reserves increased = (500 + 0) * 0.004147 / (200 + 300.041472 - 0.004147) = 0.004146690449557940
         * new total reserves = 0 + 0.004146690449557940 = 0.004146690449557940
         * new exchange rate = 500.041472 / 500.004146690449557940 = 1.000074
         */
        ib.accrueInterest(address(market2));
        assertEq(ib.getExchangeRate(address(market2)), 1.000074e6);
        assertEq(ib.getTotalCash(address(market2)), 200e6);
        assertEq(ib.getTotalBorrow(address(market2)), 300.041472e6);
        assertEq(ib.getTotalSupply(address(market2)), 500e18);
        assertEq(ib.getTotalReserves(address(market2)), 0.00414669044955794e18);

        // Now market2 exchange rate is larger than 1. Repay the debt and redeem all to see how the exchange rate changes.

        vm.startPrank(user1);
        market2.approve(address(ib), type(uint256).max);
        ib.repay(user1, user1, address(market2), type(uint256).max);
        vm.stopPrank();

        vm.prank(admin);
        ib.redeem(admin, admin, address(market2), type(uint256).max);

        /**
         * admin market2 amount = 500 * 1.000074 = 500.037
         * total cash = 500.041472 - 500.037 = 0.004472
         * total borrow = 0
         * total supply = 0
         * total reserve = 0.004146690449557940
         * new exchange rate = 0.004472 / 0.004146690449557940 = 1.078450
         *
         * (In this case, the exchange rate will grow quite a lot when the market decimals is much smaller than 1e18.)
         */
        assertEq(ib.getExchangeRate(address(market2)), 1.07845e6);
        assertEq(ib.getTotalCash(address(market2)), 0.004472e6);
        assertEq(ib.getTotalBorrow(address(market2)), 0);
        assertEq(ib.getTotalSupply(address(market2)), 0);
        assertEq(ib.getTotalReserves(address(market2)), 0.00414669044955794e18);
    }

    function testExchangeRate1e18SupplyAndRedeem() public {
        // In compound v2, cToken decimal is 8, if the underlying token decimal is larger than 8,
        // it could make the exchange rate smaller when the total supply is extremely small.
        // Here, we limit the market decimal to be smaller or equal to 18 and ibToken decimal to 18, so we're good.
        uint256 supplyAmount = 100.123123123123123123e18;
        uint256 redeemAmount = supplyAmount - 1;

        vm.startPrank(user1);
        market1.approve(address(ib), supplyAmount);
        ib.supply(user1, user1, address(market1), supplyAmount);
        ib.redeem(user1, user1, address(market1), redeemAmount);
        vm.stopPrank();

        assertEq(ib.getExchangeRate(address(market1)), 10 ** underlyingDecimals1);
        assertEq(ib.getTotalCash(address(market1)), 1);
        assertEq(ib.getTotalBorrow(address(market1)), 0);
        assertEq(ib.getTotalSupply(address(market1)), 1);
    }

    function testExchangeRate1e18SupplyAndRedeem2() public {
        // Admin provides market1 liquidity and user1 borrows market1 against market2.
        // After 1 day, user1 repays the debt and makes market1 exchange rate larger than 1.
        uint256 market2SupplyAmount = 3000 * (10 ** underlyingDecimals2);
        uint256 market1BorrowAmount = 300 * (10 ** underlyingDecimals1);
        uint256 market1SupplyAmount = 500 * (10 ** underlyingDecimals1);

        vm.startPrank(admin);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(admin, admin, address(market1), market1SupplyAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        market2.approve(address(ib), market2SupplyAmount);
        ib.supply(user1, user1, address(market2), market2SupplyAmount);
        ib.borrow(user1, user1, address(market1), market1BorrowAmount);

        fastForwardTime(86400);

        market1.approve(address(ib), type(uint256).max);
        ib.repay(user1, user1, address(market1), type(uint256).max);
        vm.stopPrank();

        uint256 exchangeRate = ib.getExchangeRate(address(market1));
        assertGt(exchangeRate, 10 ** underlyingDecimals1);

        // Now market1 exchange rate is larger than 1. Test user1 supplies and redeems the same amount.

        uint256 supplyAmount = 100.123123123123123123e18;

        vm.startPrank(user1);
        market1.approve(address(ib), supplyAmount);
        ib.supply(user1, user1, address(market1), supplyAmount);
        ib.redeem(user1, user1, address(market1), type(uint256).max);
        vm.stopPrank();

        assertEq(ib.getExchangeRate(address(market1)), exchangeRate); // exchange rate won't change
        assertEq(ibToken1.balanceOf(user1), 0);
    }

    function testExchangeRate1e18SupplyAndBorrow() public {
        // Admin provides market1 liquidity and user1 borrows market1 against market2.

        uint256 market2SupplyAmount = 3000 * (10 ** underlyingDecimals2);
        uint256 market1BorrowAmount = 300 * (10 ** underlyingDecimals1);
        uint256 market1SupplyAmount = 500 * (10 ** underlyingDecimals1);

        vm.startPrank(admin);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(admin, admin, address(market1), market1SupplyAmount);
        vm.stopPrank();

        assertEq(ib.getExchangeRate(address(market1)), 10 ** underlyingDecimals1);

        vm.startPrank(user1);
        market2.approve(address(ib), market2SupplyAmount);
        ib.supply(user1, user1, address(market2), market2SupplyAmount);
        ib.borrow(user1, user1, address(market1), market1BorrowAmount);
        vm.stopPrank();

        assertEq(ib.getExchangeRate(address(market1)), 10 ** underlyingDecimals1);

        fastForwardTime(86400);

        /**
         * utilization = 300 / 500 = 60% < kink1 = 80%
         * borrow rate = 0.000000001 + 0.6 * 0.000000001 = 0.0000000016
         * borrow interest = 0.0000000016 * 86400 * 300 = 0.041472
         * fee increased = 0.041472 * 0.1 = 0.0041472
         *
         * new total borrow = 300.041472
         * reserves increased = (500 + 0) * 0.0041472 / (200 + 300.041472 - 0.0041472) = 0.004146890436287687
         * new total reserves = 0 + 0.004146890436287687 = 0.004146890436287687
         * new exchange rate = 500.041472 / 500.004146890436287687 = 1.0000746496
         */
        ib.accrueInterest(address(market1));
        assertEq(ib.getExchangeRate(address(market1)), 1.0000746496e18);
        assertEq(ib.getTotalCash(address(market1)), 200e18);
        assertEq(ib.getTotalBorrow(address(market1)), 300.041472e18);
        assertEq(ib.getTotalSupply(address(market1)), 500e18);
        assertEq(ib.getTotalReserves(address(market1)), 0.004146890436287687e18);

        // Now market1 exchange rate is larger than 1. Repay the debt and redeem all to see how the exchange rate changes.

        vm.startPrank(user1);
        market1.approve(address(ib), type(uint256).max);
        ib.repay(user1, user1, address(market1), type(uint256).max);
        vm.stopPrank();

        vm.prank(admin);
        ib.redeem(admin, admin, address(market1), type(uint256).max);

        /**
         * admin market1 amount = 500 * 1.0000746496 = 500.0373248
         * total cash = 500.041472 - 500.0373248 = 0.0041472
         * total borrow = 0
         * total supply = 0
         * total reserve = 0.004146890436287687
         * new exchange rate = 0.0041472 / 0.004146890436287687 = 1.000074649600000072
         */
        assertEq(ib.getExchangeRate(address(market1)), 1.000074649600000072e18);
        assertEq(ib.getTotalCash(address(market1)), 0.0041472e18);
        assertEq(ib.getTotalBorrow(address(market1)), 0);
        assertEq(ib.getTotalSupply(address(market1)), 0);
        assertEq(ib.getTotalReserves(address(market1)), 0.004146890436287687e18);
    }

    function testExchangeRate1e18SupplyAndBorrowNoReserve() public {
        // Admin provides market3 liquidity and user1 borrows market3 against market2.

        uint256 market2SupplyAmount = 3000 * (10 ** underlyingDecimals2);
        uint256 market3BorrowAmount = 300 * (10 ** underlyingDecimals3);
        uint256 market3SupplyAmount = 500 * (10 ** underlyingDecimals3);

        vm.startPrank(admin);
        market3.approve(address(ib), market3SupplyAmount);
        ib.supply(admin, admin, address(market3), market3SupplyAmount);
        vm.stopPrank();

        assertEq(ib.getExchangeRate(address(market3)), 10 ** underlyingDecimals3);

        vm.startPrank(user1);
        market2.approve(address(ib), market2SupplyAmount);
        ib.supply(user1, user1, address(market2), market2SupplyAmount);
        ib.borrow(user1, user1, address(market3), market3BorrowAmount);
        vm.stopPrank();

        assertEq(ib.getExchangeRate(address(market3)), 10 ** underlyingDecimals3);

        fastForwardTime(86400);

        /**
         * utilization = 300 / 500 = 60% < kink1 = 80%
         * borrow rate = 0.000000001 + 0.6 * 0.000000001 = 0.0000000016
         * borrow interest = 0.0000000016 * 86400 * 300 = 0.041472
         *
         * new total borrow = 300.041472
         * new total supply = 500
         * new exchange rate = 500.041472 / 500 = 1.000082944
         */
        ib.accrueInterest(address(market3));
        assertEq(ib.getExchangeRate(address(market3)), 1.000082944e18);
        assertEq(ib.getTotalCash(address(market3)), 200e18);
        assertEq(ib.getTotalBorrow(address(market3)), 300.041472e18);
        assertEq(ib.getTotalSupply(address(market3)), 500e18);
        assertEq(ib.getTotalReserves(address(market3)), 0);

        // Now market3 exchange rate is larger than 1. Repay the debt and redeem all to see how the exchange rate changes.

        vm.startPrank(user1);
        market3.approve(address(ib), type(uint256).max);
        ib.repay(user1, user1, address(market3), type(uint256).max);
        vm.stopPrank();

        vm.prank(admin);
        ib.redeem(admin, admin, address(market3), type(uint256).max);

        /**
         * admin market3 amount = 500 * 1.000082944 = 500.041472
         * total cash = 500.041472 - 500.041472 = 0
         * total borrow = 0
         * total supply = 500 - 500 = 0
         * new exchange rate = 1
         */
        assertEq(ib.getExchangeRate(address(market3)), 1e18);
        assertEq(ib.getTotalCash(address(market3)), 0);
        assertEq(ib.getTotalBorrow(address(market3)), 0);
        assertEq(ib.getTotalSupply(address(market3)), 0);
        assertEq(ib.getTotalReserves(address(market3)), 0);
    }

    function testExchangeRate1e6ManipulationFailed() public {
        // Provides sufficient liquidity to prevent exchange rate manipulation.
        uint256 market2SupplyAmount = 10 * 10 ** underlyingDecimals2;

        vm.startPrank(admin);
        market2.approve(address(ib), market2SupplyAmount);
        ib.supply(admin, admin, address(market2), market2SupplyAmount);
        ibToken2.transfer(user1, 10 ** (18 - underlyingDecimals2) - 1);
        vm.stopPrank();

        vm.startPrank(user1);
        ib.redeem(user1, user1, address(market2), type(uint256).max);
        vm.stopPrank();

        /**
         * admin market2 amount = 10
         * total cash = 10 - 0 = 10
         * total borrow = 0
         * total supply = 10 - 0.000000999999999999 = 9.999999000000000001
         * new exchange rate = 10 / 9.999999000000000001 = 1.000000_1 (truncate to 1e6)
         */
        assertEq(ib.getExchangeRate(address(market2)), 10 ** underlyingDecimals2);
        assertEq(ib.getTotalCash(address(market2)), market2SupplyAmount);
        assertEq(ib.getTotalBorrow(address(market2)), 0);
        assertEq(ib.getTotalSupply(address(market2)), ibToken2.balanceOf(admin));
        assertEq(ib.getTotalReserves(address(market2)), 0);
    }

    function testExchangeRate1e6Manipulation() public {
        uint256 market2SupplyAmount = 1;

        vm.startPrank(admin);
        market2.approve(address(ib), market2SupplyAmount);
        ib.supply(admin, admin, address(market2), market2SupplyAmount);
        ibToken2.transfer(user1, 1);
        vm.stopPrank();

        vm.startPrank(admin);
        ib.redeem(admin, admin, address(market2), type(uint256).max);
        vm.stopPrank();

        /**
         * admin market2 amount = 0.999999
         * total cash = 0.000001
         * total borrow = 0
         * total supply = 1 wei
         * new exchange rate = 10 ** (-6) / 10 ** (-18) = 10 ** 12
         */
        // exchange rate has been manipulated 10^12 times
        assertEq(ib.getExchangeRate(address(market2)), 10 ** (underlyingDecimals2 + 12));
        assertEq(ib.getTotalCash(address(market2)), 1);
        assertEq(ib.getTotalBorrow(address(market2)), 0);
        assertEq(ib.getTotalSupply(address(market2)), 1);
        assertEq(ib.getTotalReserves(address(market2)), 0);
    }

    function testExchangeRate1e18OnlyReserves() public {
        uint256 donateAmount = 100 * (10 ** underlyingDecimals1);

        vm.prank(admin);
        market1.transfer(address(ib), donateAmount);

        vm.prank(reserveManager);
        ib.absorbToReserves(address(market1));

        /**
         * total cash = 100
         * total borrow = 0
         * total supply = 0
         * total reserves = 100
         * exchange rate = 1
         */
        assertEq(ib.getExchangeRate(address(market1)), 1e18);
        assertEq(ib.getTotalCash(address(market1)), 100e18);
        assertEq(ib.getTotalBorrow(address(market1)), 0);
        assertEq(ib.getTotalSupply(address(market1)), 0);
        assertEq(ib.getTotalReserves(address(market1)), 100e18);
    }
}
