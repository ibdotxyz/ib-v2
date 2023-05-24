// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract EnterExitMarketTest is Test, Common {
    uint8 internal constant underlyingDecimals = 18; // 1e18
    uint16 internal constant reserveFactor = 1000; // 10%

    int256 internal constant market1Price = 1500e8;
    int256 internal constant market2Price = 200e8;
    uint16 internal constant market1CollateralFactor = 8000; // 80%
    uint16 internal constant market2CollateralFactor = 6000; // 60%

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    FeedRegistry registry;
    PriceOracle oracle;

    ERC20Market market1;
    ERC20Market market2;
    IBToken ibToken1;
    IBToken ibToken2;
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

        (market1, ibToken1, debtToken1) =
            createAndListERC20Market(underlyingDecimals, admin, ib, configurator, irm, reserveFactor);
        (market2, ibToken2, debtToken2) =
            createAndListERC20Market(underlyingDecimals, admin, ib, configurator, irm, reserveFactor);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);
        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.USD, market2Price);

        configureMarketAsCollateral(admin, configurator, address(market1), market1CollateralFactor);
        configureMarketAsCollateral(admin, configurator, address(market2), market2CollateralFactor);

        deal(address(market1), user1, 10_000 * (10 ** underlyingDecimals));
        deal(address(market2), user1, 10_000 * (10 ** underlyingDecimals));
        deal(address(market1), user2, 10_000 * (10 ** underlyingDecimals));
        deal(address(market2), user2, 10_000 * (10 ** underlyingDecimals));
    }

    function testSupplyAndBorrow() public {
        uint256 market1SupplyAmount = 100 * (10 ** underlyingDecimals);
        uint256 market2BorrowAmount = 500 * (10 ** underlyingDecimals);

        vm.startPrank(user2);
        market2.approve(address(ib), market2BorrowAmount);

        vm.expectEmit(true, true, false, true, address(ib));
        emit MarketEntered(address(market2), user2);

        ib.supply(user2, user2, address(market2), market2BorrowAmount);

        address[] memory user2EnteredMarkets = ib.getUserEnteredMarkets(user2);
        assertEq(user2EnteredMarkets.length, 1);
        assertEq(user2EnteredMarkets[0], address(market2));
        vm.stopPrank();

        vm.startPrank(user1);
        market1.approve(address(ib), market1SupplyAmount);

        vm.expectEmit(true, true, false, true, address(ib));
        emit MarketEntered(address(market1), user1);

        ib.supply(user1, user1, address(market1), market1SupplyAmount);

        address[] memory user1EnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(user1EnteredMarkets.length, 1);
        assertEq(user1EnteredMarkets[0], address(market1));

        vm.expectEmit(true, true, false, true, address(ib));
        emit MarketEntered(address(market2), user1);

        ib.borrow(user1, user1, address(market2), market2BorrowAmount);

        user1EnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(user1EnteredMarkets.length, 2);
        assertEq(user1EnteredMarkets[0], address(market1));
        assertEq(user1EnteredMarkets[1], address(market2));
        vm.stopPrank();
    }

    function testRedeemAndRepay() public {
        uint256 market1SupplyAmount = 100 * (10 ** underlyingDecimals);
        uint256 market2BorrowAmount = 500 * (10 ** underlyingDecimals);

        vm.startPrank(user2);
        market2.approve(address(ib), market2BorrowAmount);

        vm.expectEmit(true, true, false, true, address(ib));
        emit MarketEntered(address(market2), user2);

        ib.supply(user2, user2, address(market2), market2BorrowAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        market1.approve(address(ib), market1SupplyAmount);

        vm.expectEmit(true, true, false, true, address(ib));
        emit MarketEntered(address(market1), user1);

        ib.supply(user1, user1, address(market1), market1SupplyAmount);

        vm.expectEmit(true, true, false, true, address(ib));
        emit MarketEntered(address(market2), user1);

        ib.borrow(user1, user1, address(market2), market2BorrowAmount);

        market2.approve(address(ib), type(uint256).max);

        vm.expectEmit(true, true, false, true, address(ib));
        emit MarketExited(address(market2), user1);

        ib.repay(user1, user1, address(market2), type(uint256).max);

        address[] memory userEnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(userEnteredMarkets.length, 1);
        assertEq(userEnteredMarkets[0], address(market1));

        vm.expectEmit(true, true, false, true, address(ib));
        emit MarketExited(address(market1), user1);

        ib.redeem(user1, user1, address(market1), type(uint256).max);

        userEnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(userEnteredMarkets.length, 0);
    }

    function testTransferIBToken() public {
        uint256 market1SupplyAmount = 100 * (10 ** underlyingDecimals);

        vm.startPrank(user1);
        market1.approve(address(ib), market1SupplyAmount);

        vm.expectEmit(true, true, false, true, address(ib));
        emit MarketEntered(address(market1), user1);

        ib.supply(user1, user1, address(market1), market1SupplyAmount);

        address[] memory user1EnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(user1EnteredMarkets.length, 1);
        assertEq(user1EnteredMarkets[0], address(market1));

        vm.expectEmit(true, true, false, true, address(ib));
        emit MarketEntered(address(market1), user2);
        vm.expectEmit(true, true, false, true, address(ib));
        emit MarketExited(address(market1), user1);

        ibToken1.transfer(user2, ibToken1.balanceOf(user1));

        user1EnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(user1EnteredMarkets.length, 0);

        address[] memory user2EnteredMarkets = ib.getUserEnteredMarkets(user2);
        assertEq(user2EnteredMarkets.length, 1);
        assertEq(user2EnteredMarkets[0], address(market1));
        vm.stopPrank();
    }

    function testExitMarket1() public {
        uint256 market1SupplyAmount = 100 * (10 ** underlyingDecimals);
        uint256 market1BorrowAmount = 10 * (10 ** underlyingDecimals);

        vm.startPrank(user1);
        market1.approve(address(ib), type(uint256).max);
        ib.supply(user1, user1, address(market1), market1SupplyAmount);
        ib.borrow(user1, user1, address(market1), market1BorrowAmount);

        address[] memory user1EnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(user1EnteredMarkets.length, 1);
        assertEq(user1EnteredMarkets[0], address(market1));

        ib.repay(user1, user1, address(market1), type(uint256).max);
        // No borrow but has supply, so still the market is entered.
        assertTrue(ib.getSupplyBalance(user1, address(market1)) > 0);
        assertEq(ib.getBorrowBalance(user1, address(market1)), 0);

        user1EnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(user1EnteredMarkets.length, 1);
        assertEq(user1EnteredMarkets[0], address(market1));

        vm.expectEmit(true, true, false, true, address(ib));
        emit MarketExited(address(market1), user1);

        ib.redeem(user1, user1, address(market1), type(uint256).max);

        user1EnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(user1EnteredMarkets.length, 0);

        ib.redeem(user1, user1, address(market1), 0); // nothing happens

        user1EnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(user1EnteredMarkets.length, 0);
        vm.stopPrank();
    }

    function testExitMarket2() public {
        uint256 market1SupplyAmount = 100 * (10 ** underlyingDecimals);
        uint256 market1BorrowAmount = 10 * (10 ** underlyingDecimals);
        uint256 market2SupplyAmount = 1000 * (10 ** underlyingDecimals);

        vm.startPrank(admin);
        // Faucet some market1 for user1 to redeem full later.
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(admin, admin, address(market1), market1SupplyAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        market1.approve(address(ib), type(uint256).max);
        ib.supply(user1, user1, address(market1), market1SupplyAmount);
        ib.borrow(user1, user1, address(market1), market1BorrowAmount);

        address[] memory user1EnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(user1EnteredMarkets.length, 1);
        assertEq(user1EnteredMarkets[0], address(market1));

        market2.approve(address(ib), market2SupplyAmount);
        ib.supply(user1, user1, address(market2), market2SupplyAmount);
        ib.redeem(user1, user1, address(market1), type(uint256).max);
        // No supply but has borrow, so still the market is entered.
        assertEq(ib.getSupplyBalance(user1, address(market1)), 0);
        assertTrue(ib.getBorrowBalance(user1, address(market1)) > 0);

        user1EnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(user1EnteredMarkets.length, 2);
        assertEq(user1EnteredMarkets[0], address(market1));
        assertEq(user1EnteredMarkets[1], address(market2));

        vm.expectEmit(true, true, false, true, address(ib));
        emit MarketExited(address(market1), user1);

        ib.repay(user1, user1, address(market1), type(uint256).max);

        user1EnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(user1EnteredMarkets.length, 1);
        assertEq(user1EnteredMarkets[0], address(market2));

        ib.repay(user1, user1, address(market1), 0); // nothing happens

        user1EnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(user1EnteredMarkets.length, 1);
        assertEq(user1EnteredMarkets[0], address(market2));
        vm.stopPrank();
    }
}
