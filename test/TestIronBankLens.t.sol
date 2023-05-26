// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract BorrowTest is Test, Common {
    uint16 internal constant reserveFactor = 1000; // 10%

    int256 internal constant market1Price = 1500e8;
    int256 internal constant market2Price = 200e8;
    uint16 internal constant market1CollateralFactor = 8000; // 80%

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    TripleSlopeRateModel irm;
    FeedRegistry registry;
    PriceOracle oracle;
    IronBankLens lens;

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

        irm = createDefaultIRM();

        (market1, ibToken1, debtToken1) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);
        (market2, ibToken2, debtToken2) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);
        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.USD, market2Price);

        configureMarketAsCollateral(admin, configurator, address(market1), market1CollateralFactor);

        lens = createLens();

        deal(address(market1), user1, 10000e18);
        deal(address(market2), user2, 10000e18);

        uint256 market1SupplyAmount = 100e18;
        uint256 market2BorrowAmount = 300e18;
        uint256 market2SupplyAmount = 500e18;

        vm.startPrank(user2);
        market2.approve(address(ib), market2SupplyAmount);
        ib.supply(user2, user2, address(market2), market2SupplyAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user1, user1, address(market1), market1SupplyAmount);
        ib.borrow(user1, user1, address(market2), market2BorrowAmount);
        vm.stopPrank();
    }

    function testGetMarketMetadata() public {
        IronBankLens.MarketMetadata memory metadata = lens.getMarketMetadata(ib, address(market1));

        assertEq(metadata.market, address(market1));
        assertEq(metadata.marketName, "Token");
        assertEq(metadata.marketSymbol, "TOKEN");
        assertEq(metadata.marketDecimals, 18);
        assertTrue(metadata.isListed);
        assertEq(metadata.collateralFactor, market1CollateralFactor);
        assertEq(metadata.liquidationThreshold, market1CollateralFactor);
        assertEq(metadata.liquidationBonus, 11000); // 110%
        assertEq(metadata.reserveFactor, reserveFactor);
        assertFalse(metadata.isPToken);
        assertFalse(metadata.supplyPaused);
        assertFalse(metadata.borrowPaused);
        assertFalse(metadata.transferPaused);
        assertFalse(metadata.isSoftDelisted);
        assertEq(metadata.ibTokenAddress, address(ibToken1));
        assertEq(metadata.debtTokenAddress, address(debtToken1));
        assertEq(metadata.pTokenAddress, address(0));
        assertEq(metadata.interestRateModelAddress, address(irm));
        assertEq(metadata.supplyCap, 0);
        assertEq(metadata.borrowCap, 0);
    }

    function testGetAllMarketsMetadata() public {
        IronBankLens.MarketMetadata[] memory metadatas = lens.getAllMarketsMetadata(ib);

        assertEq(metadatas.length, 2);
        assertEq(metadatas[0].market, address(market1));
        assertEq(metadatas[0].marketName, "Token");
        assertEq(metadatas[0].marketSymbol, "TOKEN");
        assertEq(metadatas[0].marketDecimals, 18);
        assertTrue(metadatas[0].isListed);
        assertEq(metadatas[0].collateralFactor, market1CollateralFactor);
        assertEq(metadatas[0].liquidationThreshold, market1CollateralFactor);
        assertEq(metadatas[0].liquidationBonus, 11000); // 110%
        assertEq(metadatas[0].reserveFactor, reserveFactor);
        assertFalse(metadatas[0].isPToken);
        assertFalse(metadatas[0].supplyPaused);
        assertFalse(metadatas[0].borrowPaused);
        assertFalse(metadatas[0].transferPaused);
        assertFalse(metadatas[0].isSoftDelisted);
        assertEq(metadatas[0].ibTokenAddress, address(ibToken1));
        assertEq(metadatas[0].debtTokenAddress, address(debtToken1));
        assertEq(metadatas[0].pTokenAddress, address(0));
        assertEq(metadatas[0].interestRateModelAddress, address(irm));
        assertEq(metadatas[0].supplyCap, 0);
        assertEq(metadatas[0].borrowCap, 0);
        assertEq(metadatas[1].market, address(market2));
        assertEq(metadatas[1].marketName, "Token");
        assertEq(metadatas[1].marketSymbol, "TOKEN");
        assertEq(metadatas[1].marketDecimals, 18);
        assertTrue(metadatas[1].isListed);
        assertEq(metadatas[1].collateralFactor, 0);
        assertEq(metadatas[1].liquidationThreshold, 0);
        assertEq(metadatas[1].liquidationBonus, 0);
        assertEq(metadatas[1].reserveFactor, reserveFactor);
        assertFalse(metadatas[1].isPToken);
        assertFalse(metadatas[1].supplyPaused);
        assertFalse(metadatas[1].borrowPaused);
        assertFalse(metadatas[1].transferPaused);
        assertFalse(metadatas[1].isSoftDelisted);
        assertEq(metadatas[1].ibTokenAddress, address(ibToken2));
        assertEq(metadatas[1].debtTokenAddress, address(debtToken2));
        assertEq(metadatas[1].pTokenAddress, address(0));
        assertEq(metadatas[1].interestRateModelAddress, address(irm));
        assertEq(metadatas[1].supplyCap, 0);
        assertEq(metadatas[1].borrowCap, 0);
    }

    function testGetMarketStatus() public {
        IronBankLens.MarketStatus memory status = lens.getMarketStatus(ib, address(market2));

        assertEq(status.market, address(market2));
        assertEq(status.totalCash, 200e18); // 500 - 300
        assertEq(status.totalBorrow, 300e18);
        assertEq(status.totalSupply, 500e18);
        assertEq(status.totalReserves, 0);
        assertEq(status.maxSupplyAmount, type(uint256).max);
        assertEq(status.maxBorrowAmount, 200e18);
        assertEq(status.marketPrice, 200e18); // price is normalized
        assertEq(status.exchangeRate, 1e18);
        assertEq(status.supplyRate, irm.getSupplyRate(200e18, 300e18));
        assertEq(status.borrowRate, irm.getBorrowRate(200e18, 300e18));

        // supplyCap > totalSupplyUnderlying
        uint256 supplyCap = 600e18;

        vm.prank(admin);
        configurator.setMarketSupplyCaps(constructMarketCapArgument(address(market2), supplyCap));

        status = lens.getMarketStatus(ib, address(market2));
        assertEq(status.maxSupplyAmount, 100e18);

        // supplyCap <= totalSupplyUnderlying
        supplyCap = 500e18;

        vm.prank(admin);
        configurator.setMarketSupplyCaps(constructMarketCapArgument(address(market2), supplyCap));

        status = lens.getMarketStatus(ib, address(market2));
        assertEq(status.maxSupplyAmount, 0);

        // borrowCap > totalBorrow, gap > totalCash
        uint256 borrowCap = 600e18;

        vm.prank(admin);
        configurator.setMarketBorrowCaps(constructMarketCapArgument(address(market2), borrowCap));

        status = lens.getMarketStatus(ib, address(market2));
        assertEq(status.maxBorrowAmount, 200e18);

        // borrowCap > totalBorrow, gap < totalCash
        borrowCap = 400e18;

        vm.prank(admin);
        configurator.setMarketBorrowCaps(constructMarketCapArgument(address(market2), borrowCap));

        status = lens.getMarketStatus(ib, address(market2));
        assertEq(status.maxBorrowAmount, 100e18);

        // borrowCap <= totalBorrow
        borrowCap = 300e18;

        vm.prank(admin);
        configurator.setMarketBorrowCaps(constructMarketCapArgument(address(market2), borrowCap));

        status = lens.getMarketStatus(ib, address(market2));
        assertEq(status.maxBorrowAmount, 0);
    }

    function testGetCurrentMarketStatus() public {
        fastForwardTime(86400);

        (bool success, bytes memory data) = address(lens).call(
            abi.encodeWithSignature("getCurrentMarketStatus(address,address)", address(ib), address(market2))
        );
        assertTrue(success);

        /**
         * utilization = 300 / 500 = 60% < kink1 = 80%
         * borrow rate = 0.000000001 + 0.6 * 0.000000001 = 0.0000000016
         * borrow interest = 0.0000000016 * 86400 * 300 = 0.041472
         * fee = 0.041472 * 0.1 = 0.0041472
         * total borrow = 300 + 0.041472 = 300.041472
         * total reserves = 0 + 500 * 0.0041472 / (200 + 300 + 0.041472 - 0.0041472) = 0.004146890436287687
         * exchange rate = (200 + 300.041472) / (500 + 0.004146890436287687) = 1.0000746496
         */
        IronBankLens.MarketStatus memory status = abi.decode(data, (IronBankLens.MarketStatus));
        assertEq(status.market, address(market2));
        assertEq(status.totalCash, 200e18); // 500 - 300
        assertEq(status.totalBorrow, 300.041472e18);
        assertEq(status.totalSupply, 500e18);
        assertEq(status.totalReserves, 0.004146890436287687e18);
        assertEq(status.maxSupplyAmount, type(uint256).max);
        assertEq(status.maxBorrowAmount, 200e18);
        assertEq(status.marketPrice, 200e18); // price is normalized
        assertEq(status.exchangeRate, 1.0000746496e18);
        assertEq(status.supplyRate, irm.getSupplyRate(200e18, 300.041472e18));
        assertEq(status.borrowRate, irm.getBorrowRate(200e18, 300.041472e18));
    }

    function testGetAllMarketStatus() public {
        IronBankLens.MarketStatus[] memory status = lens.getAllMarketsStatus(ib);

        assertEq(status.length, 2);
        assertEq(status[0].market, address(market1));
        assertEq(status[0].totalCash, 100e18);
        assertEq(status[0].totalBorrow, 0);
        assertEq(status[0].totalSupply, 100e18);
        assertEq(status[0].totalReserves, 0);
        assertEq(status[0].maxSupplyAmount, type(uint256).max);
        assertEq(status[0].maxBorrowAmount, 100e18);
        assertEq(status[0].marketPrice, 1500e18); // price is normalized
        assertEq(status[0].exchangeRate, 1e18);
        assertEq(status[0].supplyRate, irm.getSupplyRate(100e18, 0));
        assertEq(status[0].borrowRate, irm.getBorrowRate(100e18, 0));
        assertEq(status[1].market, address(market2));
        assertEq(status[1].totalCash, 200e18); // 500 - 300
        assertEq(status[1].totalBorrow, 300e18);
        assertEq(status[1].totalSupply, 500e18);
        assertEq(status[1].totalReserves, 0);
        assertEq(status[1].maxSupplyAmount, type(uint256).max);
        assertEq(status[1].maxBorrowAmount, 200e18);
        assertEq(status[1].marketPrice, 200e18); // price is normalized
        assertEq(status[1].exchangeRate, 1e18);
        assertEq(status[1].supplyRate, irm.getSupplyRate(200e18, 300e18));
        assertEq(status[1].borrowRate, irm.getBorrowRate(200e18, 300e18));
    }

    function testGetAllCurrentMarketStatus() public {
        fastForwardTime(86400);

        (bool success, bytes memory data) =
            address(lens).call(abi.encodeWithSignature("getAllCurrentMarketsStatus(address)", address(ib)));
        assertTrue(success);

        IronBankLens.MarketStatus[] memory status = abi.decode(data, (IronBankLens.MarketStatus[]));
        assertEq(status.length, 2);

        assertEq(status[0].market, address(market1));
        assertEq(status[0].totalCash, 100e18);
        assertEq(status[0].totalBorrow, 0);
        assertEq(status[0].totalSupply, 100e18);
        assertEq(status[0].totalReserves, 0);
        assertEq(status[0].maxSupplyAmount, type(uint256).max);
        assertEq(status[0].maxBorrowAmount, 100e18);
        assertEq(status[0].marketPrice, 1500e18); // price is normalized
        assertEq(status[0].exchangeRate, 1e18);
        assertEq(status[0].supplyRate, irm.getSupplyRate(100e18, 0));
        assertEq(status[0].borrowRate, irm.getBorrowRate(100e18, 0));

        /**
         * utilization = 300 / 500 = 60% < kink1 = 80%
         * borrow rate = 0.000000001 + 0.6 * 0.000000001 = 0.0000000016
         * borrow interest = 0.0000000016 * 86400 * 300 = 0.041472
         * fee = 0.041472 * 0.1 = 0.0041472
         * total borrow = 300 + 0.041472 = 300.041472
         * total reserves = 0 + 500 * 0.0041472 / (200 + 300 + 0.041472 - 0.0041472) = 0.004146890436287687
         * exchange rate = (200 + 300.041472) / (500 + 0.004146890436287687) = 1.0000746496
         */
        assertEq(status[1].market, address(market2));
        assertEq(status[1].totalCash, 200e18); // 500 - 300
        assertEq(status[1].totalBorrow, 300.041472e18);
        assertEq(status[1].totalSupply, 500e18);
        assertEq(status[1].totalReserves, 0.004146890436287687e18);
        assertEq(status[1].maxSupplyAmount, type(uint256).max);
        assertEq(status[1].maxBorrowAmount, 200e18);
        assertEq(status[1].marketPrice, 200e18); // price is normalized
        assertEq(status[1].exchangeRate, 1.0000746496e18);
        assertEq(status[1].supplyRate, irm.getSupplyRate(200e18, 300.041472e18));
        assertEq(status[1].borrowRate, irm.getBorrowRate(200e18, 300.041472e18));
    }

    function testGetUserMarketStatus() public {
        IronBankLens.UserMarketStatus memory status = lens.getUserMarketStatus(ib, user1, address(market2));

        assertEq(status.market, address(market2));
        assertEq(status.balance, 300e18); // borrow 300
        assertEq(status.allowanceToIronBank, 0);
        assertEq(status.exchangeRate, 1e18);
        assertEq(status.ibTokenBalance, 0);
        assertEq(status.supplyBalance, 0);
        assertEq(status.borrowBalance, 300e18);
    }

    function testCurrentGetUserMarketStatus() public {
        fastForwardTime(86400);

        (bool success, bytes memory data) = address(lens).call(
            abi.encodeWithSignature(
                "getCurrentUserMarketStatus(address,address,address)", address(ib), user1, address(market2)
            )
        );
        assertTrue(success);

        IronBankLens.UserMarketStatus memory status = abi.decode(data, (IronBankLens.UserMarketStatus));

        assertEq(status.market, address(market2));
        assertEq(status.balance, 300e18); // borrow 300
        assertEq(status.allowanceToIronBank, 0);
        assertEq(status.exchangeRate, 1.0000746496e18);
        assertEq(status.ibTokenBalance, 0);
        assertEq(status.supplyBalance, 0);
        assertEq(status.borrowBalance, 300.041472e18);
    }

    function testGetUserAllMarketsStatus() public {
        IronBankLens.UserMarketStatus[] memory status = lens.getUserAllMarketsStatus(ib, user1);

        assertEq(status.length, 2);
        assertEq(status[0].market, address(market1));
        assertEq(status[0].balance, 9900e18); // 10000 - 100
        assertEq(status[0].allowanceToIronBank, 0);
        assertEq(status[0].exchangeRate, 1e18);
        assertEq(status[0].ibTokenBalance, 100e18);
        assertEq(status[0].supplyBalance, 100e18);
        assertEq(status[0].borrowBalance, 0);
        assertEq(status[1].market, address(market2));
        assertEq(status[1].balance, 300e18); // borrow 300
        assertEq(status[1].allowanceToIronBank, 0);
        assertEq(status[1].exchangeRate, 1e18);
        assertEq(status[1].ibTokenBalance, 0);
        assertEq(status[1].supplyBalance, 0);
        assertEq(status[1].borrowBalance, 300e18);
    }

    function testGetUserAllCurrentMarketsStatus() public {
        fastForwardTime(86400);

        (bool success, bytes memory data) = address(lens).call(
            abi.encodeWithSignature("getUserAllCurrentMarketsStatus(address,address)", address(ib), user1)
        );
        assertTrue(success);

        IronBankLens.UserMarketStatus[] memory status = abi.decode(data, (IronBankLens.UserMarketStatus[]));

        assertEq(status.length, 2);
        assertEq(status[0].market, address(market1));
        assertEq(status[0].balance, 9900e18); // 10000 - 100
        assertEq(status[0].allowanceToIronBank, 0);
        assertEq(status[0].exchangeRate, 1e18);
        assertEq(status[0].ibTokenBalance, 100e18);
        assertEq(status[0].supplyBalance, 100e18);
        assertEq(status[0].borrowBalance, 0);
        assertEq(status[1].market, address(market2));
        assertEq(status[1].balance, 300e18); // borrow 300
        assertEq(status[1].allowanceToIronBank, 0);
        assertEq(status[1].exchangeRate, 1.0000746496e18);
        assertEq(status[1].ibTokenBalance, 0);
        assertEq(status[1].supplyBalance, 0);
        assertEq(status[1].borrowBalance, 300.041472e18);
    }
}
