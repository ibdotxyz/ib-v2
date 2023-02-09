// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../src/protocol/pool/interest-rate-model/TripleSlopeRateModel.sol";
import "../src/protocol/pool/IronBank.sol";
import "../src/protocol/pool/IronBankProxy.sol";
import "../src/protocol/pool/IronBankStorage.sol";
import "../src/protocol/pool/MarketConfigurator.sol";
import "../src/protocol/token/IBToken.sol";
import "../src/protocol/token/DebtToken.sol";

contract ListDelistTest is Test {
    uint256 internal constant baseRatePerSecond = 0.0001e18;
    uint256 internal constant borrowPerSecond1 = 0.002e18;
    uint256 internal constant kink1 = 0.8e18;
    uint256 internal constant borrowPerSecond2 = 0.004e18;
    uint256 internal constant kink2 = 0.9e18;
    uint256 internal constant borrowPerSecond3 = 0.006e18;
    uint256 internal constant initialExchangeRate = 1e18;
    uint16 internal constant maxReserveFactor = 10000; // 100%;
    uint16 internal constant reserveFactor = 1000; // 10%
    uint16 internal constant collateralFactor = 7000; // 70%

    IronBank ib;
    MarketConfigurator configurator;
    TripleSlopeRateModel irm;

    address admin = address(64);
    address user1 = address(128);

    function setUp() public {
        IronBank impl = new IronBank();
        IronBankProxy proxy = new IronBankProxy(address(impl), "");
        ib = IronBank(address(proxy));
        ib.initialize(admin);

        configurator = new MarketConfigurator(address(ib));
        configurator.transferOwnership(admin);
        vm.prank(admin);
        configurator.acceptOwnership();

        ib.setMarketConfigurator(address(configurator));

        irm = new TripleSlopeRateModel(
            baseRatePerSecond,
            borrowPerSecond1,
            kink1,
            borrowPerSecond2,
            kink2,
            borrowPerSecond3
        );
    }

    function createIBToken(address _admin, address _pool, address _underlying) internal returns (IBToken) {
        IBToken impl = new IBToken();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        IBToken ibToken = IBToken(address(proxy));
        ibToken.initialize("Iron Bank Token", "ibToken", _admin, _pool, _underlying);
        return ibToken;
    }

    function createDebtToken(address _admin, address _pool, address _underlying) internal returns (DebtToken) {
        DebtToken impl = new DebtToken();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        DebtToken debtToken = DebtToken(address(proxy));
        debtToken.initialize("Iron Bank Debt Token", "debtToken", _admin, _pool, _underlying);
        return debtToken;
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

        vm.prank(admin);
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );

        vm.prank(admin);
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

        vm.prank(admin);
        vm.expectRevert("mismatch underlying");
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );

        ibToken = createIBToken(admin, address(ib), address(market));

        vm.prank(admin);
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

        vm.prank(admin);
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );

        vm.prank(admin);
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

        vm.prank(admin);
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );

        // Soft delist by separate actions.
        vm.prank(admin);
        configurator.setSupplyPaused(address(market), true);
        vm.prank(admin);
        configurator.setBorrowPaused(address(market), true);
        vm.prank(admin);
        configurator.adjustMarketReserveFactor(address(market), maxReserveFactor);
        vm.prank(admin);
        configurator.adjustMarketCollateralFactor(address(market), 0);

        // Won't revert to call soft delist again.
        vm.prank(admin);
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

        vm.prank(admin);
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );

        vm.prank(admin);
        configurator.softDelistMarket(address(market));

        vm.prank(admin);
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

        vm.prank(admin);
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );

        vm.prank(admin);
        vm.expectRevert("not paused");
        configurator.hardDelistMarket(address(market));
    }

    function testCannotHardDelistForReserveFactorNotMax() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        vm.prank(admin);
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );

        vm.prank(admin);
        configurator.setSupplyPaused(address(market), true);
        vm.prank(admin);
        configurator.setBorrowPaused(address(market), true);

        vm.prank(admin);
        vm.expectRevert("reserve factor not max");
        configurator.hardDelistMarket(address(market));
    }

    function testCannotHardDelistForCollateralFactorNotZero() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        vm.prank(admin);
        configurator.listMarket(
            address(market), address(ibToken), address(debtToken), address(irm), reserveFactor, initialExchangeRate
        );

        vm.prank(admin);
        configurator.setSupplyPaused(address(market), true);
        vm.prank(admin);
        configurator.setBorrowPaused(address(market), true);
        vm.prank(admin);
        configurator.adjustMarketReserveFactor(address(market), maxReserveFactor);
        vm.prank(admin);
        configurator.adjustMarketCollateralFactor(address(market), collateralFactor);

        vm.prank(admin);
        vm.expectRevert("collateral factor not zero");
        configurator.hardDelistMarket(address(market));
    }
}
