// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract IronBankAdminTest is Test, Common {
    IronBank ib;

    address admin = address(64);
    address user1 = address(128);

    function setUp() public {
        ib = createIronBank(admin);
    }

    function testAdmin() public {
        assertEq(ib.owner(), admin);
    }

    function testSetPriceOracle() public {
        PriceOracle oracle = new PriceOracle(address(0));

        vm.prank(admin);
        vm.expectEmit(false, false, false, true, address(ib));
        emit PriceOracleSet(address(oracle));

        ib.setPriceOracle(address(oracle));
        assertEq(ib.priceOracle(), address(oracle));
    }

    function testCannotSetPriceOracleForNotOwner() public {
        PriceOracle oracle = new PriceOracle(address(0));

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        ib.setPriceOracle(address(oracle));
    }

    function testSetMarketConfigurator() public {
        MarketConfigurator configurator = new MarketConfigurator(address(ib));

        vm.prank(admin);
        vm.expectEmit(false, false, false, true, address(ib));
        emit MarketConfiguratorSet(address(configurator));

        ib.setMarketConfigurator(address(configurator));
        assertEq(ib.marketConfigurator(), address(configurator));
    }

    function testCannotSetMarketConfiguratorForNotOwner() public {
        MarketConfigurator configurator = new MarketConfigurator(address(ib));

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        ib.setMarketConfigurator(address(configurator));
    }

    function testSetCreditLimitManager() public {
        CreditLimitManager creditLimitManager = new CreditLimitManager(address(ib));

        vm.prank(admin);
        vm.expectEmit(false, false, false, true, address(ib));
        emit CreditLimitManagerSet(address(creditLimitManager));

        ib.setCreditLimitManager(address(creditLimitManager));
        assertEq(ib.creditLimitManager(), address(creditLimitManager));
    }

    function testCannotSetCreditLimitManagerForNotOwner() public {
        CreditLimitManager creditLimitManager = new CreditLimitManager(address(ib));

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        ib.setCreditLimitManager(address(creditLimitManager));
    }

    function testSetReserveManager() public {
        address reserveManager = user1;

        vm.prank(admin);
        vm.expectEmit(false, false, false, true, address(ib));
        emit ReserveManagerSet(reserveManager);

        ib.setReserveManager(reserveManager);
        assertEq(ib.reserveManager(), reserveManager);
    }

    function testCannotSetReserveManagerForNotOwner() public {
        address reserveManager = user1;

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        ib.setReserveManager(reserveManager);
    }

    function testSeize() public {
        ERC20 notListedMarket = new ERC20Market("Token", "TOKEN", 18, admin);

        vm.prank(admin);
        notListedMarket.transfer(address(ib), 100e18);

        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(ib));
        emit TokenSeized(address(notListedMarket), user1, 100e18);

        ib.seize(address(notListedMarket), user1);
        assertEq(notListedMarket.balanceOf(user1), 100e18);
    }

    function testCannotSeizeForNotOwner() public {
        ERC20 notListedMarket = new ERC20Market("Token", "TOKEN", 18, admin);

        vm.prank(admin);
        notListedMarket.transfer(address(ib), 100e18);

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        ib.seize(address(notListedMarket), user1);
    }

    function testCannotSeizeForListedMarket() public {
        uint16 reserveFactor = 1000; // 10%

        MarketConfigurator configurator = createMarketConfigurator(admin, ib);

        vm.prank(admin);
        ib.setMarketConfigurator(address(configurator));

        TripleSlopeRateModel irm = createDefaultIRM();

        (ERC20Market market,,) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);

        vm.prank(admin);
        market.transfer(address(ib), 100e18);

        vm.prank(admin);
        vm.expectRevert("cannot seize listed market");
        ib.seize(address(market), user1);
    }
}
