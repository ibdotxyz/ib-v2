// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract EnterExitMarketTest is Test, Common {
    uint8 internal constant underlyingDecimals = 18; // 1e18
    uint256 internal constant initialExchangeRate = 1e16; // 1 underlying -> 100 ibToken
    uint16 internal constant reserveFactor = 1000; // 10%

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;

    ERC20Market market1;
    ERC20Market market2;
    ERC20Market market3;
    ERC20Market market4;

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

        (market1,,) = createAndListERC20Market(
            underlyingDecimals, admin, ib, configurator, irm, reserveFactor, initialExchangeRate
        );
        (market2,,) = createAndListERC20Market(
            underlyingDecimals, admin, ib, configurator, irm, reserveFactor, initialExchangeRate
        );
        (market3,,) = createAndListERC20Market(
            underlyingDecimals, admin, ib, configurator, irm, reserveFactor, initialExchangeRate
        );
        (market4,,) = createAndListERC20Market(
            underlyingDecimals, admin, ib, configurator, irm, reserveFactor, initialExchangeRate
        );

        vm.startPrank(admin);
        market1.transfer(user1, 10_000 * (10 ** underlyingDecimals));
        vm.stopPrank();
    }

    function testEnterMarket() public {
        vm.startPrank(user1);
        ib.enterMarket(user1, address(market1));

        assertTrue(ib.isEnteredMarket(user1, address(market1)));

        address[] memory userEnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(userEnteredMarkets.length, 1);
        assertEq(userEnteredMarkets[0], address(market1));

        ib.enterMarket(user1, address(market1)); // Enter again.
        ib.enterMarket(user1, address(market2));
        vm.stopPrank();

        assertTrue(ib.isEnteredMarket(user1, address(market1)));
        assertTrue(ib.isEnteredMarket(user1, address(market2)));

        userEnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(userEnteredMarkets.length, 2);
        assertEq(userEnteredMarkets[0], address(market1));
        assertEq(userEnteredMarkets[1], address(market2));
    }

    function testEnterMarketAndIncreaseCollateral() public {
        uint256 supplyAmount = 100 * (10 ** underlyingDecimals);

        vm.startPrank(user1);
        market1.approve(address(ib), supplyAmount);
        ib.supply(user1, address(market1), supplyAmount);
        assertEq(ib.getUserCollateralBalance(user1, address(market1)), 0);

        ib.enterMarket(user1, address(market1));
        assertEq(ib.getUserCollateralBalance(user1, address(market1)), 10000e18);
        vm.stopPrank();

        assertTrue(ib.isEnteredMarket(user1, address(market1)));

        address[] memory userEnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(userEnteredMarkets.length, 1);
        assertEq(userEnteredMarkets[0], address(market1));
    }

    function testCannotEnterMarketForUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert("!authorized");
        ib.enterMarket(user2, address(market1));
    }

    function testCannotEnterMarketForMarketNotListed() public {
        ERC20 invalidMarket = new ERC20("Token", "TOKEN");

        vm.prank(user1);
        vm.expectRevert("not listed");
        ib.enterMarket(user1, address(invalidMarket));
    }

    function testCannotEnterMarketForMarketFrozen() public {
        vm.prank(admin);
        configurator.freezeMarket(address(market1), true);

        vm.prank(user1);
        vm.expectRevert("frozen");
        ib.enterMarket(user1, address(market1));
    }

    function testExitMarket() public {
        vm.startPrank(user1);
        ib.enterMarket(user1, address(market1));
        ib.exitMarket(user1, address(market1));
        vm.stopPrank();

        assertFalse(ib.isEnteredMarket(user1, address(market1)));

        assertEq(ib.getUserEnteredMarkets(user1).length, 0);
    }

    function testExitMarket2() public {
        vm.startPrank(user1);
        ib.enterMarket(user1, address(market1));
        ib.enterMarket(user1, address(market2));
        ib.enterMarket(user1, address(market3));

        ib.exitMarket(user1, address(market3));
        assertFalse(ib.isEnteredMarket(user1, address(market3)));

        ib.exitMarket(user1, address(market1));
        assertFalse(ib.isEnteredMarket(user1, address(market1)));

        ib.exitMarket(user1, address(market1)); // Exit again.
        assertFalse(ib.isEnteredMarket(user1, address(market1)));
        vm.stopPrank();

        assertTrue(ib.isEnteredMarket(user1, address(market2)));

        address[] memory userEnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(userEnteredMarkets.length, 1);
        assertEq(userEnteredMarkets[0], address(market2));
    }

    function testExitMarketAndDecreaseCollateral() public {
        uint256 supplyAmount = 100 * (10 ** underlyingDecimals);

        vm.startPrank(user1);
        market1.approve(address(ib), supplyAmount);
        ib.supply(user1, address(market1), supplyAmount);
        ib.enterMarket(user1, address(market1));
        ib.exitMarket(user1, address(market1));
        vm.stopPrank();

        assertFalse(ib.isEnteredMarket(user1, address(market1)));

        address[] memory userEnteredMarkets = ib.getUserEnteredMarkets(user1);
        assertEq(userEnteredMarkets.length, 0);
    }

    function testCannotExitMarketForUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert("!authorized");
        ib.exitMarket(user2, address(market1));
    }

    function testCannotExitMarketForMarketNotListed() public {
        ERC20 invalidMarket = new ERC20("Token", "TOKEN");

        vm.prank(user1);
        vm.expectRevert("not listed");
        ib.exitMarket(user1, address(invalidMarket));
    }

    function testCannotExitMarketForMarketFrozen() public {
        vm.prank(admin);
        configurator.freezeMarket(address(market1), true);

        vm.prank(user1);
        vm.expectRevert("frozen");
        ib.exitMarket(user1, address(market1));
    }

    function testCannotExitMarketForHavingBorrowBalance() public {
        uint256 borrowAmount = 500 * (10 ** underlyingDecimals);

        vm.startPrank(admin);
        market1.approve(address(ib), borrowAmount);
        ib.supply(admin, address(market1), borrowAmount);
        creditLimitManager.setCreditLimit(user1, address(market1), borrowAmount);
        vm.stopPrank();

        vm.prank(user1);
        ib.borrow(user1, address(market1), borrowAmount);

        vm.prank(user1);
        vm.expectRevert("borrow balance not zero");
        ib.exitMarket(user1, address(market1));
    }

    function testCannotExitMarketForInsufficientCollateral() public {
        int256 market1Price = 1500e8;
        int256 market2Price = 200e8;
        uint16 market1CollateralFactor = 8000; // 80%

        FeedRegistry registry = createRegistry();
        PriceOracle oracle = createPriceOracle(admin, address(registry));
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);
        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.USD, market2Price);

        setMarketCollateralFactor(admin, configurator, address(market1), market1CollateralFactor);

        uint256 market1SupplyAmount = 100 * (10 ** underlyingDecimals);
        uint256 market2BorrowAmount = 500 * (10 ** underlyingDecimals);

        vm.startPrank(admin);
        market2.approve(address(ib), market2BorrowAmount);
        ib.supply(admin, address(market2), market2BorrowAmount);
        market1.transfer(user1, market1SupplyAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user1, address(market1), market1SupplyAmount);
        ib.enterMarket(user1, address(market1));
        ib.borrow(user1, address(market2), market2BorrowAmount);

        vm.expectRevert("insufficient collateral");
        ib.exitMarket(user1, address(market1));
        vm.stopPrank();
    }
}
