// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract ReservesTest is Test, Common {
    uint16 internal constant reserveFactor = 1000; // 10%

    int256 internal constant market1Price = 1500e8;

    IronBank ib;
    MarketConfigurator configurator;
    FeedRegistry registry;
    PriceOracle oracle;

    ERC20Market market;

    address admin = address(64);
    address reserveManager = address(128);
    address user1 = address(256);

    function setUp() public {
        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);

        vm.prank(admin);
        ib.setMarketConfigurator(address(configurator));

        TripleSlopeRateModel irm = createDefaultIRM();

        (market,,) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market), address(market), Denominations.USD, market1Price);

        vm.prank(admin);
        ib.setReserveManager(reserveManager);

        deal(address(market), user1, 10000e18);
    }

    function testAbsorbToReserves() public {
        uint256 supplyAmount = 100e18;

        vm.startPrank(user1);
        market.approve(address(ib), supplyAmount);
        ib.supply(user1, user1, address(market), supplyAmount);

        uint256 donateAmount = 200e18;
        market.transfer(address(ib), donateAmount);
        vm.stopPrank();

        assertEq(market.balanceOf(address(ib)), 300e18);
        assertEq(ib.getTotalCash(address(market)), 100e18);
        assertEq(ib.getTotalSupply(address(market)), 100e18);
        assertEq(ib.getTotalReserves(address(market)), 0);
        assertEq(ib.getExchangeRate(address(market)), 1e18);

        vm.prank(reserveManager);
        vm.expectEmit(true, false, false, true, address(ib));
        emit ReservesIncreased(address(market), donateAmount, donateAmount);

        ib.absorbToReserves(address(market));

        assertEq(market.balanceOf(address(ib)), 300e18);
        assertEq(ib.getTotalCash(address(market)), 300e18);
        assertEq(ib.getTotalSupply(address(market)), 100e18);
        assertEq(ib.getTotalReserves(address(market)), 200e18);
        assertEq(ib.getExchangeRate(address(market)), 1e18); // exchange rate is not affected
    }

    function testAbsorbToReservesWithNoSurplusAmount() public {
        uint256 supplyAmount = 100e18;

        vm.startPrank(user1);
        market.approve(address(ib), supplyAmount);
        ib.supply(user1, user1, address(market), supplyAmount);
        vm.stopPrank();

        assertEq(market.balanceOf(address(ib)), 100e18);
        assertEq(ib.getTotalCash(address(market)), 100e18);
        assertEq(ib.getTotalSupply(address(market)), 100e18);
        assertEq(ib.getTotalReserves(address(market)), 0);
        assertEq(ib.getExchangeRate(address(market)), 1e18);

        vm.prank(reserveManager);
        ib.absorbToReserves(address(market));

        // Nothing changed.
        assertEq(market.balanceOf(address(ib)), 100e18);
        assertEq(ib.getTotalCash(address(market)), 100e18);
        assertEq(ib.getTotalSupply(address(market)), 100e18);
        assertEq(ib.getTotalReserves(address(market)), 0);
        assertEq(ib.getExchangeRate(address(market)), 1e18);
    }

    function testCannotAbsorbToReservesForNotReserveManager() public {
        vm.prank(user1);
        vm.expectRevert("!reserveManager");
        ib.absorbToReserves(address(market));
    }

    function testCannotAbsorbToReservesForMarketNotListed() public {
        ERC20 notListedMarket = new ERC20("Token", "TOKEN");

        vm.prank(reserveManager);
        vm.expectRevert("not listed");
        ib.absorbToReserves(address(notListedMarket));
    }

    function testReduceReserves() public {
        uint256 supplyAmount = 100e18;

        vm.startPrank(user1);
        market.approve(address(ib), supplyAmount);
        ib.supply(user1, user1, address(market), supplyAmount);

        uint256 donateAmount = 200e18;
        market.transfer(address(ib), donateAmount);
        vm.stopPrank();

        vm.startPrank(reserveManager);
        vm.expectEmit(true, false, false, true, address(ib));
        emit ReservesIncreased(address(market), donateAmount, donateAmount);

        ib.absorbToReserves(address(market));

        assertEq(market.balanceOf(address(ib)), 300e18);
        assertEq(ib.getTotalCash(address(market)), 300e18);
        assertEq(ib.getTotalSupply(address(market)), 100e18);
        assertEq(ib.getTotalReserves(address(market)), 200e18);

        uint256 reduceAmount = 100e18;

        vm.expectEmit(true, true, false, true, address(ib));
        emit ReservesDecreased(address(market), reserveManager, reduceAmount, reduceAmount);

        ib.reduceReserves(address(market), reduceAmount, reserveManager);

        assertEq(market.balanceOf(address(ib)), 200e18);
        assertEq(ib.getTotalCash(address(market)), 200e18);
        assertEq(ib.getTotalSupply(address(market)), 100e18);
        assertEq(ib.getTotalReserves(address(market)), 100e18);
        assertEq(market.balanceOf(reserveManager), 100e18);
        vm.stopPrank();
    }

    function testCannotReduceReservesForNotReserveManager() public {
        vm.prank(user1);
        vm.expectRevert("!reserveManager");
        ib.reduceReserves(address(market), 100e18, reserveManager);
    }

    function testCannotReduceReservesForMarketNotListed() public {
        ERC20 notListedMarket = new ERC20("Token", "TOKEN");

        vm.prank(reserveManager);
        vm.expectRevert("not listed");
        ib.reduceReserves(address(notListedMarket), 100e18, reserveManager);
    }

    function testCannotReduceReservesForInsufficientCash() public {
        uint256 supplyAmount = 100e18;

        vm.startPrank(user1);
        market.approve(address(ib), supplyAmount);
        ib.supply(user1, user1, address(market), supplyAmount);

        uint256 donateAmount = 200e18;
        market.transfer(address(ib), donateAmount);
        vm.stopPrank();

        vm.startPrank(reserveManager);
        ib.absorbToReserves(address(market));

        uint256 reduceAmount = 301e18;

        vm.expectRevert("insufficient cash");
        ib.reduceReserves(address(market), reduceAmount, reserveManager);
        vm.stopPrank();
    }

    function testCannotReduceReservesForInsufficientReserves() public {
        uint256 supplyAmount = 100e18;

        vm.startPrank(user1);
        market.approve(address(ib), supplyAmount);
        ib.supply(user1, user1, address(market), supplyAmount);

        uint256 donateAmount = 200e18;
        market.transfer(address(ib), donateAmount);
        vm.stopPrank();

        vm.startPrank(reserveManager);
        ib.absorbToReserves(address(market));

        uint256 reduceAmount = 201e18;

        vm.expectRevert("insufficient reserves");
        ib.reduceReserves(address(market), reduceAmount, reserveManager);
        vm.stopPrank();
    }
}
