// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract ListDelistTest is Test, Common {
    uint16 internal constant maxReserveFactor = 10000; // 100%;
    uint16 internal constant reserveFactor = 1000; // 10%
    uint16 internal constant collateralFactor = 7000; // 70%

    IronBank ib;
    MarketConfigurator configurator;
    TripleSlopeRateModel irm;

    address admin = address(64);

    function setUp() public {
        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);
        ib.setMarketConfigurator(address(configurator));

        irm = createDefaultIRM();
    }

    /* ========== List Market ========== */

    function testListMarket() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken1 = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken1 = createDebtToken(admin, address(ib), address(market));

        PToken pToken = createPToken(admin, address(market));
        IBToken ibToken2 = createIBToken(admin, address(ib), address(pToken));

        vm.prank(admin);
        configurator.listMarket(address(market), address(ibToken1), address(debtToken1), address(irm), reserveFactor);

        IronBankStorage.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        assertTrue(config.isListed);
        assertEq(config.ibTokenAddress, address(ibToken1));
        assertEq(config.debtTokenAddress, address(debtToken1));
        assertEq(config.interestRateModelAddress, address(irm));
        assertEq(config.reserveFactor, reserveFactor);
        assertFalse(config.isPToken);
        assertEq(config.pTokenAddress, address(0));

        address[] memory markets = ib.getAllMarkets();
        assertEq(markets.length, 1);
        assertEq(markets[0], address(market));

        // List a pToken of this market.
        vm.prank(admin);
        configurator.listPTokenMarket(address(pToken), address(ibToken2), address(irm), reserveFactor);

        // Update the pToken.
        config = ib.getMarketConfiguration(address(market));
        assertEq(config.pTokenAddress, address(pToken));

        config = ib.getMarketConfiguration(address(pToken));
        assertTrue(config.isListed);
        assertEq(config.ibTokenAddress, address(ibToken2));
        assertEq(config.debtTokenAddress, address(0));
        assertEq(config.interestRateModelAddress, address(irm));
        assertEq(config.reserveFactor, reserveFactor);
        assertTrue(config.isPToken);
        assertEq(config.pTokenAddress, address(0));

        markets = ib.getAllMarkets();
        assertEq(markets.length, 2);
        assertEq(markets[0], address(market));
        assertEq(markets[1], address(pToken));
    }

    function testListMarket2() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken1 = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken1 = createDebtToken(admin, address(ib), address(market));

        PToken pToken = createPToken(admin, address(market));
        IBToken ibToken2 = createIBToken(admin, address(ib), address(pToken));

        // List the pToken first.
        vm.prank(admin);
        configurator.listPTokenMarket(address(pToken), address(ibToken2), address(irm), reserveFactor);

        IronBankStorage.MarketConfig memory config = ib.getMarketConfiguration(address(pToken));
        assertTrue(config.isListed);
        assertEq(config.ibTokenAddress, address(ibToken2));
        assertEq(config.debtTokenAddress, address(0));
        assertEq(config.interestRateModelAddress, address(irm));
        assertEq(config.reserveFactor, reserveFactor);
        assertTrue(config.isPToken);
        assertEq(config.pTokenAddress, address(0));

        address[] memory markets = ib.getAllMarkets();
        assertEq(markets.length, 1);
        assertEq(markets[0], address(pToken));

        // List the underlying of the pToken.
        vm.prank(admin);
        configurator.listMarket(address(market), address(ibToken1), address(debtToken1), address(irm), reserveFactor);

        config = ib.getMarketConfiguration(address(market));
        assertTrue(config.isListed);
        assertEq(config.ibTokenAddress, address(ibToken1));
        assertEq(config.debtTokenAddress, address(debtToken1));
        assertEq(config.interestRateModelAddress, address(irm));
        assertEq(config.reserveFactor, reserveFactor);
        assertFalse(config.isPToken);
        assertEq(config.pTokenAddress, address(0));

        // Update the pToken.
        vm.prank(admin);
        configurator.setMarketPToken(address(market), address(pToken));

        markets = ib.getAllMarkets();
        assertEq(markets.length, 2);
        assertEq(markets[0], address(pToken));
        assertEq(markets[1], address(market));
    }

    function testCannotListMarketForNotMarketConfigurator() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IronBankStorage.MarketConfig memory emptyConfig = ib.getMarketConfiguration(address(market));

        vm.expectRevert("!configurator");
        ib.listMarket(address(market), emptyConfig);
    }

    function testCannotListMarketForNotAdmin() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        vm.expectRevert("Ownable: caller is not the owner");
        configurator.listMarket(address(market), address(ibToken), address(debtToken), address(irm), reserveFactor);
    }

    function testCannotListMarketForAlreadyListed() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        vm.startPrank(admin);
        configurator.listMarket(address(market), address(ibToken), address(debtToken), address(irm), reserveFactor);

        vm.expectRevert("already listed");
        configurator.listMarket(address(market), address(ibToken), address(debtToken), address(irm), reserveFactor);
    }

    function testCannotListMarketForMismatchUnderlying() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        ERC20 market2 = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market2));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market2));

        vm.startPrank(admin);
        vm.expectRevert("mismatch underlying");
        configurator.listMarket(address(market), address(ibToken), address(debtToken), address(irm), reserveFactor);

        ibToken = createIBToken(admin, address(ib), address(market));

        vm.expectRevert("mismatch underlying");
        configurator.listMarket(address(market), address(ibToken), address(debtToken), address(irm), reserveFactor);
    }

    function testCannotListMarketForInvalidReserveFactor() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        uint16 invalidReserveFactor = 10001;

        vm.prank(admin);
        vm.expectRevert("invalid reserve factor");
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), invalidReserveFactor
        );
    }

    function testCannotListMarketForUnderlyingAlreadyHasPToken() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken1 = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken1 = createDebtToken(admin, address(ib), address(market));

        PToken pToken = createPToken(admin, address(market));
        IBToken ibToken2 = createIBToken(admin, address(ib), address(pToken));

        vm.startPrank(admin);
        configurator.listMarket(address(market), address(ibToken1), address(debtToken1), address(irm), reserveFactor);
        configurator.listPTokenMarket(address(pToken), address(ibToken2), address(irm), reserveFactor);

        PToken pToken2 = createPToken(admin, address(market));
        IBToken ibToken3 = createIBToken(admin, address(ib), address(pToken2));

        vm.expectRevert("underlying already has pToken");
        configurator.listPTokenMarket(address(pToken2), address(ibToken3), address(irm), reserveFactor);
        vm.stopPrank();
    }

    /* ========== Soft Delist Market ========== */

    function testSoftDelistMarket() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        vm.startPrank(admin);
        configurator.listMarket(address(market), address(ibToken), address(debtToken), address(irm), reserveFactor);

        configurator.softDelistMarket(address(market));

        IronBankStorage.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        assertTrue(config.isListed);
        assertTrue(config.supplyPaused);
        assertTrue(config.borrowPaused);
        assertEq(config.reserveFactor, maxReserveFactor);
        assertEq(config.collateralFactor, 0);
    }

    function testSoftDelistMarket2() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        vm.startPrank(admin);
        configurator.listMarket(address(market), address(ibToken), address(debtToken), address(irm), reserveFactor);

        // Soft delist by separate actions.
        configurator.setMarketSupplyPaused(address(market), true);
        configurator.setMarketBorrowPaused(address(market), true);
        configurator.adjustMarketReserveFactor(address(market), maxReserveFactor);
        configurator.adjustMarketCollateralFactor(address(market), 0);

        // Won't revert to call soft delist again.
        configurator.softDelistMarket(address(market));

        IronBankStorage.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        assertTrue(config.isListed);
        assertTrue(config.supplyPaused);
        assertTrue(config.borrowPaused);
        assertEq(config.reserveFactor, maxReserveFactor);
        assertEq(config.collateralFactor, 0);
    }

    function testCannotSoftDelistMarketForNotAdmin() public {
        ERC20 market = new ERC20("Token", "TOKEN");

        vm.expectRevert("Ownable: caller is not the owner");
        configurator.softDelistMarket(address(market));
    }

    function testCannotSoftDelistMarketForNotListed() public {
        ERC20 market = new ERC20("Token", "TOKEN");

        vm.prank(admin);
        vm.expectRevert("not listed");
        configurator.softDelistMarket(address(market));
    }

    /* ========== Hard Delist Market ========== */

    function testHardDelistMarket() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        vm.startPrank(admin);
        configurator.listMarket(address(market), address(ibToken), address(debtToken), address(irm), reserveFactor);

        configurator.softDelistMarket(address(market));
        configurator.hardDelistMarket(address(market));

        IronBankStorage.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        assertFalse(config.isListed);

        address[] memory markets = ib.getAllMarkets();
        assertEq(markets.length, 0);
        vm.stopPrank();
    }

    function testHardDelistMarket2() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        PToken pToken = createPToken(admin, address(market));
        IBToken ibToken2 = createIBToken(admin, address(ib), address(pToken));
        DebtToken debtToken2 = createDebtToken(admin, address(ib), address(pToken));

        vm.startPrank(admin);
        configurator.listMarket(address(market), address(ibToken), address(debtToken), address(irm), reserveFactor);

        configurator.listMarket(address(pToken), address(ibToken2), address(debtToken2), address(irm), reserveFactor);

        configurator.softDelistMarket(address(pToken));
        configurator.hardDelistMarket(address(pToken));

        IronBankStorage.MarketConfig memory config = ib.getMarketConfiguration(address(pToken));
        assertFalse(config.isListed);

        config = ib.getMarketConfiguration(address(market));
        assertEq(config.pTokenAddress, address(0));

        address[] memory markets = ib.getAllMarkets();
        assertEq(markets.length, 1);
        assertEq(markets[0], address(market));
        vm.stopPrank();
    }

    function testCannotHardDelistForNotMarketConfigurator() public {
        ERC20 market = new ERC20("Token", "TOKEN");

        vm.expectRevert("!configurator");
        ib.delistMarket(address(market));
    }

    function testCannotHardDelistForNotAdmin() public {
        ERC20 market = new ERC20("Token", "TOKEN");

        vm.expectRevert("Ownable: caller is not the owner");
        configurator.hardDelistMarket(address(market));
    }

    function testCannotHardDelistForNotListed() public {
        ERC20 market = new ERC20("Token", "TOKEN");

        vm.prank(admin);
        vm.expectRevert("not listed");
        configurator.hardDelistMarket(address(market));
    }

    function testCannotHardDelistForNotPaused() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        vm.startPrank(admin);
        configurator.listMarket(address(market), address(ibToken), address(debtToken), address(irm), reserveFactor);

        vm.expectRevert("not paused");
        configurator.hardDelistMarket(address(market));
    }

    function testCannotHardDelistForReserveFactorNotMax() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        vm.startPrank(admin);
        configurator.listMarket(address(market), address(ibToken), address(debtToken), address(irm), reserveFactor);

        configurator.setMarketSupplyPaused(address(market), true);
        configurator.setMarketBorrowPaused(address(market), true);

        vm.expectRevert("reserve factor not max");
        configurator.hardDelistMarket(address(market));
    }

    function testCannotHardDelistForCollateralFactorNotZero() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        vm.startPrank(admin);
        configurator.listMarket(address(market), address(ibToken), address(debtToken), address(irm), reserveFactor);

        configurator.setMarketSupplyPaused(address(market), true);
        configurator.setMarketBorrowPaused(address(market), true);
        configurator.adjustMarketReserveFactor(address(market), maxReserveFactor);
        configurator.adjustMarketCollateralFactor(address(market), collateralFactor);

        vm.expectRevert("collateral factor not zero");
        configurator.hardDelistMarket(address(market));
    }
}
