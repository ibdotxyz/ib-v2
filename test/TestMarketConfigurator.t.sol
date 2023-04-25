// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract MarketConfiguratorTest is Test, Common {
    using PauseFlags for DataTypes.MarketConfig;

    address admin = address(64);
    address user = address(128);

    IronBank ib;
    MarketConfigurator configurator;
    TripleSlopeRateModel irm;

    ERC20 market;
    ERC20 notListedMarket;

    function setUp() public {
        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);
        ib.setMarketConfigurator(address(configurator));

        irm = createDefaultIRM();

        market = new ERC20("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market));

        notListedMarket = new ERC20("Token", "TOKEN");

        uint16 reserveFactor = 1500; // 15%

        vm.prank(admin);
        configurator.listMarket(address(market), address(ibToken), address(debtToken), address(irm), reserveFactor);
    }

    function testSetGuardian() public {
        address guardian = address(256);

        vm.prank(admin);
        configurator.setGuardian(guardian);

        assertEq(configurator.guardian(), guardian);
    }

    function testCannotSetGuardianForNotOwner() public {
        address guardian = address(256);

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        configurator.setGuardian(guardian);
    }

    function testConfigureMarketAsCollateral() public {
        uint16 collateralFactor = 7000; // 70%
        uint16 liquidationThreshold = 5000; // 50%
        uint16 liquidationBonus = 11000; // 110%

        vm.prank(admin);
        configurator.configureMarketAsCollateral(
            address(market), collateralFactor, liquidationThreshold, liquidationBonus
        );

        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        assertEq(config.collateralFactor, collateralFactor);
        assertEq(config.liquidationThreshold, liquidationThreshold);
        assertEq(config.liquidationBonus, liquidationBonus);
    }

    function testCannotConfigureMarketAsCollateralForNotOwner() public {
        uint16 collateralFactor = 7000; // 70%
        uint16 liquidationThreshold = 5000; // 50%
        uint16 liquidationBonus = 11000; // 110%

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        configurator.configureMarketAsCollateral(
            address(market), collateralFactor, liquidationThreshold, liquidationBonus
        );
    }

    function testCannotConfigureMarketAsCollateralForNotListed() public {
        uint16 collateralFactor = 7000; // 70%
        uint16 liquidationThreshold = 5000; // 50%
        uint16 liquidationBonus = 11000; // 110%

        vm.prank(admin);
        vm.expectRevert("not listed");
        configurator.configureMarketAsCollateral(
            address(notListedMarket), collateralFactor, liquidationThreshold, liquidationBonus
        );
    }

    function testCannotConfigureMarketAsCollateralForAlreadyConfigured() public {
        uint16 collateralFactor = 7000; // 70%
        uint16 liquidationThreshold = 5000; // 50%
        uint16 liquidationBonus = 11000; // 110%

        vm.startPrank(admin);
        configurator.configureMarketAsCollateral(
            address(market), collateralFactor, liquidationThreshold, liquidationBonus
        );

        vm.expectRevert("already configured");
        configurator.configureMarketAsCollateral(
            address(market), collateralFactor, liquidationThreshold, liquidationBonus
        );
        vm.stopPrank();
    }

    function testCannotConfigureMarketAsCollateralForInvalidCollateralFactor() public {
        uint16 liquidationThreshold = 5000; // 50%
        uint16 liquidationBonus = 11000; // 110%

        uint16 invalidCollateralFactor = 9100; // 91%

        vm.prank(admin);
        vm.expectRevert("invalid collateral factor");
        configurator.configureMarketAsCollateral(
            address(market), invalidCollateralFactor, liquidationThreshold, liquidationBonus
        );
    }

    function testCannotConfigureMarketAsCollateralForInvalidLiquidationThreshold() public {
        uint16 collateralFactor = 7000; // 70%
        uint16 liquidationBonus = 11000; // 110%

        uint16 invalidLiquidationThreshold = 10100; // 101%

        vm.prank(admin);
        vm.expectRevert("invalid liquidation threshold");
        configurator.configureMarketAsCollateral(
            address(market), collateralFactor, invalidLiquidationThreshold, liquidationBonus
        );
    }

    function testCannotConfigureMarketAsCollateralForInvalidLiquidationBonus() public {
        uint16 collateralFactor = 7000; // 70%
        uint16 liquidationThreshold = 5000; // 50%

        uint16 invalidLiquidationBonus = 9900; // 99%

        vm.prank(admin);
        vm.expectRevert("invalid liquidation bonus");
        configurator.configureMarketAsCollateral(
            address(market), collateralFactor, liquidationThreshold, invalidLiquidationBonus
        );

        invalidLiquidationBonus = 12600; // 126%

        vm.prank(admin);
        vm.expectRevert("invalid liquidation bonus");
        configurator.configureMarketAsCollateral(
            address(market), collateralFactor, liquidationThreshold, invalidLiquidationBonus
        );
    }

    function testAdjustMarketCollateralFactor() public {
        uint16 collateralFactor = 7000; // 70%

        vm.prank(admin);
        configurator.adjustMarketCollateralFactor(address(market), collateralFactor);

        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        assertEq(config.collateralFactor, collateralFactor);
    }

    function testCannotAdjustMarketCollateralFactorForNotOwner() public {
        uint16 collateralFactor = 7000; // 70%

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        configurator.adjustMarketCollateralFactor(address(market), collateralFactor);
    }

    function testCannotAdjustMarketCollateralFactorForNotListed() public {
        uint16 collateralFactor = 7000; // 70%

        vm.prank(admin);
        vm.expectRevert("not listed");
        configurator.adjustMarketCollateralFactor(address(notListedMarket), collateralFactor);
    }

    function testCannotAdjustMarketCollateralFactorForInvalidCollateralFactor() public {
        uint16 collateralFactor = 9100; // 91%

        vm.prank(admin);
        vm.expectRevert("invalid collateral factor");
        configurator.adjustMarketCollateralFactor(address(market), collateralFactor);
    }

    function testAdjustMarketReserveFactor() public {
        uint16 reserveFactor = 1000; // 10%

        vm.prank(admin);
        configurator.adjustMarketReserveFactor(address(market), reserveFactor);

        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        assertEq(config.reserveFactor, reserveFactor);
    }

    function testAdjustMarketReserveFactorForNotOwner() public {
        uint16 reserveFactor = 1000; // 10%

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        configurator.adjustMarketReserveFactor(address(market), reserveFactor);
    }

    function testAdjustMarketReserveFactorForNotListed() public {
        uint16 reserveFactor = 1000; // 10%

        vm.prank(admin);
        vm.expectRevert("not listed");
        configurator.adjustMarketReserveFactor(address(notListedMarket), reserveFactor);
    }

    function testAdjustMarketReserveFactorForInvalidReserveFactor() public {
        uint16 reserveFactor = 11000; // 110%

        vm.prank(admin);
        vm.expectRevert("invalid reserve factor");
        configurator.adjustMarketReserveFactor(address(market), reserveFactor);
    }

    function testAdjustMarketLiquidationThreshold() public {
        uint16 liquidationThreshold = 5000; // 50%

        vm.prank(admin);
        configurator.adjustMarketLiquidationThreshold(address(market), liquidationThreshold);

        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        assertEq(config.liquidationThreshold, liquidationThreshold);
    }

    function testAdjustMarketLiquidationThresholdForNotOwner() public {
        uint16 liquidationThreshold = 5000; // 50%

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        configurator.adjustMarketLiquidationThreshold(address(market), liquidationThreshold);
    }

    function testAdjustMarketLiquidationThresholdForNotListed() public {
        uint16 liquidationThreshold = 5000; // 50%

        vm.prank(admin);
        vm.expectRevert("not listed");
        configurator.adjustMarketLiquidationThreshold(address(notListedMarket), liquidationThreshold);
    }

    function testAdjustMarketLiquidationThresholdForInvalidLiquidationThreshold() public {
        uint16 liquidationThreshold = 10100; // 101%

        vm.prank(admin);
        vm.expectRevert("invalid liquidation threshold");
        configurator.adjustMarketLiquidationThreshold(address(market), liquidationThreshold);
    }

    function testAdjustMarketLiquidationBonus() public {
        uint16 liquidationBonus = 11000; // 110%

        vm.prank(admin);
        configurator.adjustMarketLiquidationBonus(address(market), liquidationBonus);

        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        assertEq(config.liquidationBonus, liquidationBonus);
    }

    function testAdjustMarketLiquidationBonusForNotOwner() public {
        uint16 liquidationBonus = 11000; // 110%

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        configurator.adjustMarketLiquidationBonus(address(market), liquidationBonus);
    }

    function testAdjustMarketLiquidationBonusForNotListed() public {
        uint16 liquidationBonus = 11000; // 110%

        vm.prank(admin);
        vm.expectRevert("not listed");
        configurator.adjustMarketLiquidationBonus(address(notListedMarket), liquidationBonus);
    }

    function testAdjustMarketLiquidationBonusForInvalidLiquidationBonus() public {
        uint16 liquidationBonus = 9900; // 99%

        vm.prank(admin);
        vm.expectRevert("invalid liquidation bonus");
        configurator.adjustMarketLiquidationBonus(address(market), liquidationBonus);

        liquidationBonus = 12600; // 126%

        vm.prank(admin);
        vm.expectRevert("invalid liquidation bonus");
        configurator.adjustMarketLiquidationBonus(address(market), liquidationBonus);
    }

    function testChangeMarketInterestRateModel() public {
        TripleSlopeRateModel newIrm = createDefaultIRM();

        vm.prank(admin);
        configurator.changeMarketInterestRateModel(address(market), address(newIrm));

        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        assertEq(config.interestRateModelAddress, address(newIrm));
    }

    function testCannotChangeMarketInterestRateModelForNotOwner() public {
        TripleSlopeRateModel newIrm = createDefaultIRM();

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        configurator.changeMarketInterestRateModel(address(market), address(newIrm));
    }

    function testCannotChangeMarketInterestRateModelForNotListed() public {
        TripleSlopeRateModel newIrm = createDefaultIRM();

        vm.prank(admin);
        vm.expectRevert("not listed");
        configurator.changeMarketInterestRateModel(address(notListedMarket), address(newIrm));
    }

    function testSetMarketTransferPaused() public {
        vm.prank(admin);
        configurator.setMarketTransferPaused(address(market), true);

        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        assertTrue(config.isTransferPaused());
    }

    function testCannotSetMarketTransferPausedForNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        configurator.setMarketTransferPaused(address(market), true);
    }

    function testCannotSetMarketTransferPausedForNotListed() public {
        vm.prank(admin);
        vm.expectRevert("not listed");
        configurator.setMarketTransferPaused(address(notListedMarket), true);
    }

    function testSetMarketSupplyCaps() public {
        uint256 supplyCap = 100;

        vm.prank(admin);
        configurator.setMarketSupplyCaps(constructMarketCapArgument(address(market), supplyCap));

        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        assertEq(config.supplyCap, supplyCap);

        address guardian = address(256);
        supplyCap = 200;

        vm.prank(admin);
        configurator.setGuardian(guardian);

        vm.prank(guardian);
        configurator.setMarketSupplyCaps(constructMarketCapArgument(address(market), supplyCap));

        config = ib.getMarketConfiguration(address(market));
        assertEq(config.supplyCap, supplyCap);
    }

    function testCannotSetMarketSupplyCapsForNotOwnerOrGuardian() public {
        uint256 supplyCap = 100;

        vm.prank(user);
        vm.expectRevert("!authorized");
        configurator.setMarketSupplyCaps(constructMarketCapArgument(address(market), supplyCap));
    }

    function testCannotSetMarketSupplyCapsForNotListed() public {
        uint256 supplyCap = 100;

        vm.prank(admin);
        vm.expectRevert("not listed");
        configurator.setMarketSupplyCaps(constructMarketCapArgument(address(notListedMarket), supplyCap));
    }

    function testSetMarketBorrowCaps() public {
        uint256 borrowCap = 100;

        vm.prank(admin);
        configurator.setMarketBorrowCaps(constructMarketCapArgument(address(market), borrowCap));

        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        assertEq(config.borrowCap, borrowCap);

        address guardian = address(256);
        borrowCap = 200;

        vm.prank(admin);
        configurator.setGuardian(guardian);

        vm.prank(guardian);
        configurator.setMarketBorrowCaps(constructMarketCapArgument(address(market), borrowCap));

        config = ib.getMarketConfiguration(address(market));
        assertEq(config.borrowCap, borrowCap);
    }

    function testCannotSetMarketBorrowCapsForNotOwnerOrGuardian() public {
        uint256 borrowCap = 100;

        vm.prank(user);
        vm.expectRevert("!authorized");
        configurator.setMarketBorrowCaps(constructMarketCapArgument(address(market), borrowCap));
    }

    function testCannotSetMarketBorrowCapsForNotListed() public {
        uint256 borrowCap = 100;

        vm.prank(admin);
        vm.expectRevert("not listed");
        configurator.setMarketBorrowCaps(constructMarketCapArgument(address(notListedMarket), borrowCap));
    }

    function testSetMarketSupplyPaused() public {
        vm.prank(admin);
        configurator.setMarketSupplyPaused(address(market), true);

        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        assertTrue(config.isSupplyPaused());
    }

    function testCannotSetMarketSupplyPausedForNotOwner() public {
        vm.prank(user);
        vm.expectRevert("!authorized");
        configurator.setMarketSupplyPaused(address(market), true);
    }

    function testCannotSetMarketSupplyPausedForNotListed() public {
        vm.prank(admin);
        vm.expectRevert("not listed");
        configurator.setMarketSupplyPaused(address(notListedMarket), true);
    }

    function testSetMarketBorrowPaused() public {
        vm.prank(admin);
        configurator.setMarketBorrowPaused(address(market), true);

        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        assertTrue(config.isBorrowPaused());
    }

    function testCannotSetMarketBorrowPausedForNotOwner() public {
        vm.prank(user);
        vm.expectRevert("!authorized");
        configurator.setMarketBorrowPaused(address(market), true);
    }

    function testCannotSetMarketBorrowPausedForNotListed() public {
        vm.prank(admin);
        vm.expectRevert("not listed");
        configurator.setMarketBorrowPaused(address(notListedMarket), true);
    }

    function testCannotSetMarketBorrowPausedForPToken() public {
        uint16 reserveFactor = 1000; // 10%

        PToken pToken = createPToken(admin, address(market));
        IBToken ibToken2 = createIBToken(admin, address(ib), address(pToken));

        vm.startPrank(admin);
        configurator.listPTokenMarket(address(pToken), address(ibToken2), address(irm), reserveFactor);

        vm.expectRevert("cannot set borrow paused for pToken");
        configurator.setMarketBorrowPaused(address(pToken), false);
        vm.stopPrank();
    }

    function testSetMarketPToken() public {
        uint16 reserveFactor = 1000; // 10%

        ERC20 market2 = new ERC20("Token", "TOKEN");
        IBToken ibToken1 = createIBToken(admin, address(ib), address(market2));
        DebtToken debtToken1 = createDebtToken(admin, address(ib), address(market2));

        PToken pToken = createPToken(admin, address(market2));
        IBToken ibToken2 = createIBToken(admin, address(ib), address(pToken));

        // List the pToken first.
        vm.startPrank(admin);
        configurator.listPTokenMarket(address(pToken), address(ibToken2), address(irm), reserveFactor);

        // List the underlying of the pToken.
        configurator.listMarket(address(market2), address(ibToken1), address(debtToken1), address(irm), reserveFactor);

        configurator.setMarketPToken(address(market2), address(pToken));
        vm.stopPrank();

        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market2));
        assertEq(config.pTokenAddress, address(pToken));
    }

    function testCannotSetMarketPTokenForNotOwner() public {
        PToken pToken = createPToken(admin, address(market));

        vm.prank(user);
        vm.expectRevert("!authorized");
        configurator.setMarketPToken(address(market), address(pToken));
    }

    function testCannotSetMarketPTokenForMismatchPToken() public {
        ERC20 market2 = new ERC20("Token", "TOKEN");
        PToken pToken = createPToken(admin, address(market2));

        vm.prank(admin);
        vm.expectRevert("mismatch pToken");
        configurator.setMarketPToken(address(market), address(pToken));
    }

    function testCannotSetMarketPTokenForPTokenNotListed() public {
        PToken pToken = createPToken(admin, address(market));

        vm.prank(admin);
        vm.expectRevert("pToken not listed");
        configurator.setMarketPToken(address(market), address(pToken));
    }

    function testCannotSetMarketPTokenForNotListed() public {
        uint16 reserveFactor = 1000; // 10%

        PToken pToken = createPToken(admin, address(notListedMarket));
        IBToken ibToken2 = createIBToken(admin, address(ib), address(pToken));
        DebtToken debtToken2 = createDebtToken(admin, address(ib), address(pToken));

        vm.startPrank(admin);
        configurator.listMarket(address(pToken), address(ibToken2), address(debtToken2), address(irm), reserveFactor);

        vm.expectRevert("not listed");
        configurator.setMarketPToken(address(notListedMarket), address(pToken));
        vm.stopPrank();
    }

    function testCannotSetMarketPTokenForPTokenAlreadySet() public {
        uint16 reserveFactor = 1000; // 10%

        ERC20 market2 = new ERC20("Token", "TOKEN");
        IBToken ibToken1 = createIBToken(admin, address(ib), address(market2));
        DebtToken debtToken1 = createDebtToken(admin, address(ib), address(market2));

        PToken pToken = createPToken(admin, address(market2));
        IBToken ibToken2 = createIBToken(admin, address(ib), address(pToken));

        // List the pToken first.
        vm.startPrank(admin);
        configurator.listPTokenMarket(address(pToken), address(ibToken2), address(irm), reserveFactor);

        // List the underlying of the pToken.
        configurator.listMarket(address(market2), address(ibToken1), address(debtToken1), address(irm), reserveFactor);

        // Set the pToken.
        configurator.setMarketPToken(address(market2), address(pToken));

        vm.expectRevert("pToken already set");
        configurator.setMarketPToken(address(market2), address(pToken));
        vm.stopPrank();
    }
}
