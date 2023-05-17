// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract AccrueInterestTest is Test, Common {
    uint8 internal constant underlyingDecimals1 = 18; // 1e18
    uint8 internal constant underlyingDecimals2 = 6; // 1e6
    uint16 internal constant reserveFactor = 1000; // 10%

    int256 internal constant market1Price = 1500e8;
    int256 internal constant market2Price = 200e8;
    uint16 internal constant market1CollateralFactor = 8000; // 80%
    uint16 internal constant market2CollateralFactor = 8000; // 80%

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    FeedRegistry registry;
    PriceOracle oracle;

    ERC20Market market1; // decimals: 18, reserve factor: 10%, price: 1500
    ERC20Market market2; // decimals: 6, reserve factor: 10%, price: 200
    IBToken ibToken1;
    IBToken ibToken2;

    address admin = address(64);
    address user1 = address(128);

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

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);
        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.USD, market2Price);

        configureMarketAsCollateral(admin, configurator, address(market1), market1CollateralFactor);
        configureMarketAsCollateral(admin, configurator, address(market2), market2CollateralFactor);

        deal(address(market1), user1, 10_000 * (10 ** underlyingDecimals1));
        deal(address(market2), user1, 10_000 * (10 ** underlyingDecimals2));
    }

    function testAccrueInterests() public {
        // Admin provides market1 liquidity and user1 borrows market1 against market2.

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
        vm.stopPrank();

        uint256 totalBorrow = ib.getTotalBorrow(address(market1));
        uint256 totalReserves = ib.getTotalReserves(address(market1));

        fastForwardTime(86400);

        vm.expectEmit(true, false, false, true, address(ib));
        emit InterestAccrued(
            address(market1),
            uint40(block.timestamp),
            0.0000000016e18,
            1.00013824e18, // 0.0000000016 * 86400
            300.041472e18,
            0.004146890436287687e18
        );

        /**
         * utilization = 300 / 500 = 60% < kink1 = 80%
         * borrow rate = 0.000000001 + 0.6 * 0.000000001 = 0.0000000016
         * borrow interest = 0.0000000016 * 86400 * 300 = 0.041472
         * fee increased = 0.041472 * 0.1 = 0.0041472
         *
         * new total borrow = 300.041472
         * reserves increased = (500 + 0) * 0.0041472 / (200 + 300.041472 - 0.0041472) = 0.004146890436287687
         * new total reserves = 0 + 0.004146890436287687 = 0.004146890436287687
         */
        ib.accrueInterest(address(market1));
        uint256 newTotalBorrow = ib.getTotalBorrow(address(market1));
        uint256 newTotalReserves = ib.getTotalReserves(address(market1));
        assertEq(newTotalBorrow - totalBorrow, 0.041472e18);
        assertEq(newTotalReserves - totalReserves, 0.004146890436287687e18);

        // Accrue interests again. Nothing will change.
        ib.accrueInterest(address(market1));
        uint256 newTotalBorrow2 = ib.getTotalBorrow(address(market1));
        uint256 newTotalReserves2 = ib.getTotalReserves(address(market1));
        assertEq(newTotalBorrow, newTotalBorrow2);
        assertEq(newTotalReserves, newTotalReserves2);
    }

    function testAccrueInterestsWithNoBorrow() public {
        uint256 supplyAmount = 500 * (10 ** underlyingDecimals1);

        vm.startPrank(admin);
        market1.approve(address(ib), supplyAmount);
        ib.supply(admin, admin, address(market1), supplyAmount);
        vm.stopPrank();

        uint256 totalBorrow = ib.getTotalBorrow(address(market1));
        uint256 totalReserves = ib.getTotalReserves(address(market1));

        fastForwardTime(86400);

        vm.expectEmit(true, false, false, true, address(ib));
        emit InterestAccrued(
            address(market1),
            uint40(block.timestamp),
            0.000000001e18, // base borrow rate
            1.0000864e18, // 0.000000001 * 86400
            0,
            0
        );

        ib.accrueInterest(address(market1));
        uint256 newTotalBorrow = ib.getTotalBorrow(address(market1));
        uint256 newTotalReserves = ib.getTotalReserves(address(market1));

        assertEq(newTotalBorrow, totalBorrow);
        assertEq(newTotalReserves, totalReserves);
    }

    function testCannotAccrueInterestsForMarketNotListed() public {
        ERC20 invalidMarket = new ERC20("Token", "TOKEN");

        vm.expectRevert("not listed");
        ib.accrueInterest(address(invalidMarket));
    }

    function testCannotAccrueInterestsForTimestampTooLarge() public {
        fastForwardTime(86400 * 365 * 100000); // 100,000 years later...

        vm.expectRevert("timestamp too large");
        ib.accrueInterest(address(market1));
    }
}
