// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../src/protocol/pool/interest-rate-model/TripleSlopeRateModel.sol";
import "../src/protocol/pool/IronBank.sol";
import "../src/protocol/pool/IronBankStorage.sol";
import "../src/protocol/pool/MarketConfigurator.sol";
import "../src/protocol/token/IBToken.sol";
import "../src/protocol/token/DebtToken.sol";
import "./Common.t.sol";

contract ListDelistTest is Test, Common {
    uint256 internal constant initialExchangeRate = 1e18;
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
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        vm.prank(admin);
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );

        IronBankStorage.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        assertTrue(config.isListed);
        assertEq(config.ibTokenAddress, address(ibToken));
        assertEq(config.debtTokenAddress, address(debtToken));
        assertEq(config.interestRateModelAddress, address(irm));
        assertEq(config.reserveFactor, reserveFactor);
        assertEq(config.initialExchangeRate, initialExchangeRate);

        address[] memory markets = ib.getAllMarkets();
        assertEq(markets.length, 1);
        assertEq(markets[0], address(market));
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
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );
    }

    function testCannotListMarketForAlreadyListed() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        vm.startPrank(admin);
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );

        vm.expectRevert("already listed");
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );
    }

    function testCannotListMarketForMismatchUnderlying() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        ERC20 market2 = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market2));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market2));

        vm.startPrank(admin);
        vm.expectRevert("mismatch underlying");
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );

        ibToken = createIBToken(admin, address(ib), address(market));

        vm.expectRevert("mismatch underlying");
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );
    }

    function testCannotListMarketForInvalidReserveFactor() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        uint16 invalidReserveFactor = 10001;

        vm.prank(admin);
        vm.expectRevert("invalid reserve factor");
        configurator.listMarket(
            address(market),
            address(ibToken),
            address(debtToken),
            address(irm),
            invalidReserveFactor,
            initialExchangeRate
        );
    }

    /* ========== Soft Delist Market ========== */

    function testSoftDelistMarket() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        vm.startPrank(admin);
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );

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
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );

        // Soft delist by separate actions.
        configurator.setSupplyPaused(address(market), true);
        configurator.setBorrowPaused(address(market), true);
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
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );

        configurator.softDelistMarket(address(market));
        configurator.hardDelistMarket(address(market));

        IronBankStorage.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        assertFalse(config.isListed);

        address[] memory markets = ib.getAllMarkets();
        assertEq(markets.length, 0);
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
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );

        vm.expectRevert("not paused");
        configurator.hardDelistMarket(address(market));
    }

    function testCannotHardDelistForReserveFactorNotMax() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        vm.startPrank(admin);
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );

        configurator.setSupplyPaused(address(market), true);
        configurator.setBorrowPaused(address(market), true);

        vm.expectRevert("reserve factor not max");
        configurator.hardDelistMarket(address(market));
    }

    function testCannotHardDelistForCollateralFactorNotZero() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        vm.startPrank(admin);
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );

        configurator.setSupplyPaused(address(market), true);
        configurator.setBorrowPaused(address(market), true);
        configurator.adjustMarketReserveFactor(address(market), maxReserveFactor);
        configurator.adjustMarketCollateralFactor(address(market), collateralFactor);

        vm.expectRevert("collateral factor not zero");
        configurator.hardDelistMarket(address(market));
    }
}
