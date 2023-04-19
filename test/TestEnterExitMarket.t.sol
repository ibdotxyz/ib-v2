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
        ib.setMarketConfigurator(address(configurator));

        creditLimitManager = createCreditLimitManager(admin, ib);
        ib.setCreditLimitManager(address(creditLimitManager));

        TripleSlopeRateModel irm = createDefaultIRM();

        (market1, ibToken1, debtToken1) =
            createAndListERC20Market(underlyingDecimals, admin, ib, configurator, irm, reserveFactor);
        (market2, ibToken2, debtToken2) =
            createAndListERC20Market(underlyingDecimals, admin, ib, configurator, irm, reserveFactor);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);
        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.USD, market2Price);

        setMarketCollateralFactor(admin, configurator, address(market1), market1CollateralFactor);
        setMarketCollateralFactor(admin, configurator, address(market2), market2CollateralFactor);

        vm.startPrank(admin);
        market1.transfer(user1, 10_000 * (10 ** underlyingDecimals));
        market1.transfer(user2, 10_000 * (10 ** underlyingDecimals));
        market2.transfer(user1, 10_000 * (10 ** underlyingDecimals));
        market2.transfer(user2, 10_000 * (10 ** underlyingDecimals));
        vm.stopPrank();
    }

    function testSupplyAndBorrow() public {
        uint256 market1SupplyAmount = 100 * (10 ** underlyingDecimals);
        uint256 market2BorrowAmount = 500 * (10 ** underlyingDecimals);

        vm.startPrank(user2);
        market2.approve(address(ib), market2BorrowAmount);
        ib.supply(user2, user2, address(market2), market2BorrowAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user1, user1, address(market1), market1SupplyAmount);
        ib.borrow(user1, user1, address(market2), market2BorrowAmount);

        assertTrue(ib.isEnteredMarket(user1, address(market1)));
        assertTrue(ib.isEnteredMarket(user1, address(market2)));

        address[] memory userEnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(userEnteredMarkets.length, 2);
        assertEq(userEnteredMarkets[0], address(market1));
        assertEq(userEnteredMarkets[1], address(market2));
        vm.stopPrank();
    }

    function testRedeemAndRepay() public {
        uint256 market1SupplyAmount = 100 * (10 ** underlyingDecimals);
        uint256 market2BorrowAmount = 500 * (10 ** underlyingDecimals);

        vm.startPrank(user2);
        market2.approve(address(ib), market2BorrowAmount);
        ib.supply(user2, user2, address(market2), market2BorrowAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user1, user1, address(market1), market1SupplyAmount);
        ib.borrow(user1, user1, address(market2), market2BorrowAmount);

        market2.approve(address(ib), type(uint256).max);
        ib.repay(user1, user1, address(market2), type(uint256).max);
        assertFalse(ib.isEnteredMarket(user1, address(market2)));

        ib.redeem(user1, user1, address(market1), type(uint256).max);
        assertFalse(ib.isEnteredMarket(user1, address(market1)));
    }

    function testTransferIBToken() public {
        uint256 market1SupplyAmount = 100 * (10 ** underlyingDecimals);

        vm.startPrank(user1);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user1, user1, address(market1), market1SupplyAmount);
        assertTrue(ib.isEnteredMarket(user1, address(market1)));

        ibToken1.transfer(user2, ibToken1.balanceOf(user1));
        assertFalse(ib.isEnteredMarket(user1, address(market1)));
        assertTrue(ib.isEnteredMarket(user2, address(market1)));
        vm.stopPrank();
    }

    function testTransferDebtToken() public {
        uint256 market1SupplyAmount = 100 * (10 ** underlyingDecimals);
        uint256 market2BorrowAmount = 500 * (10 ** underlyingDecimals);

        vm.startPrank(user2);
        market2.approve(address(ib), market2BorrowAmount);
        ib.supply(user2, user2, address(market2), market2BorrowAmount);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user2, user2, address(market1), market1SupplyAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user1, user1, address(market1), market1SupplyAmount);
        ib.borrow(user1, user1, address(market2), market2BorrowAmount);
        assertTrue(ib.isEnteredMarket(user1, address(market2)));
        vm.stopPrank();

        vm.startPrank(user2);
        // User2 takes the market2 debt from user1.
        debtToken2.receiveDebt(user1, debtToken2.balanceOf(user1));
        assertFalse(ib.isEnteredMarket(user1, address(market2)));
        assertTrue(ib.isEnteredMarket(user2, address(market2)));
        vm.stopPrank();
    }

    function testExitMarket1() public {
        uint256 market1SupplyAmount = 100 * (10 ** underlyingDecimals);
        uint256 market1BorrowAmount = 10 * (10 ** underlyingDecimals);

        vm.startPrank(user1);
        market1.approve(address(ib), type(uint256).max);
        ib.supply(user1, user1, address(market1), market1SupplyAmount);
        ib.borrow(user1, user1, address(market1), market1BorrowAmount);
        assertTrue(ib.isEnteredMarket(user1, address(market1)));

        ib.repay(user1, user1, address(market1), type(uint256).max);
        // No borrow but has supply, so still the market is entered.
        assertTrue(ib.getSupplyBalance(user1, address(market1)) > 0);
        assertEq(ib.getBorrowBalance(user1, address(market1)), 0);
        assertTrue(ib.isEnteredMarket(user1, address(market1)));

        ib.redeem(user1, user1, address(market1), type(uint256).max);
        assertFalse(ib.isEnteredMarket(user1, address(market1)));
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
        assertTrue(ib.isEnteredMarket(user1, address(market1)));

        market2.approve(address(ib), market2SupplyAmount);
        ib.supply(user1, user1, address(market2), market2SupplyAmount);
        ib.redeem(user1, user1, address(market1), type(uint256).max);
        // No supply but has borrow, so still the market is entered.
        assertEq(ib.getSupplyBalance(user1, address(market1)), 0);
        assertTrue(ib.getBorrowBalance(user1, address(market1)) > 0);
        assertTrue(ib.isEnteredMarket(user1, address(market1)));

        ib.repay(user1, user1, address(market1), type(uint256).max);
        assertFalse(ib.isEnteredMarket(user1, address(market1)));
        vm.stopPrank();
    }
}
