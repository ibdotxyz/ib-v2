// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract AccountLiquidityTest is Test, Common {
    uint8 internal constant underlyingDecimals1 = 18; // 1e18
    uint8 internal constant underlyingDecimals2 = 8; // 1e8
    uint16 internal constant reserveFactor = 1000; // 10%
    uint16 internal constant collateralFactor = 8000; // 80%
    int256 internal constant market1Price = 1500e8;
    int256 internal constant market2Price = 0.5e8;
    int256 internal constant ethUsdPrice = 3000e8;

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    FeedRegistry registry;
    PriceOracle oracle;

    ERC20Market market1;
    ERC20Market market2;
    IBToken ibToken1;
    IBToken ibToken2;

    address admin = address(64);
    address user = address(128);

    function setUp() public {
        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);

        vm.prank(admin);
        ib.setMarketConfigurator(address(configurator));

        creditLimitManager = createCreditLimitManager(admin, ib);

        vm.prank(admin);
        ib.setCreditLimitManager(address(creditLimitManager));

        TripleSlopeRateModel irm = createDefaultIRM();

        (market1, ibToken1,) =
            createAndListERC20Market(underlyingDecimals1, admin, ib, configurator, irm, reserveFactor);
        (market2, ibToken2,) =
            createAndListERC20Market(underlyingDecimals2, admin, ib, configurator, irm, reserveFactor);

        configureMarketAsCollateral(admin, configurator, address(market1), collateralFactor);
        configureMarketAsCollateral(admin, configurator, address(market2), collateralFactor);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);
        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.ETH, market2Price);
        setPriceToRegistry(registry, admin, Denominations.ETH, Denominations.USD, ethUsdPrice);

        deal(address(market1), user, 10_000 * (10 ** underlyingDecimals1));
        deal(address(market2), user, 10_000 * (10 ** underlyingDecimals2));
    }

    function testGetAccountLiquidity() public {
        uint256 market1SupplyAmount = 1000 * (10 ** underlyingDecimals1);
        uint256 market2SupplyAmount = 1000 * (10 ** underlyingDecimals2);

        vm.startPrank(user);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user, user, address(market1), market1SupplyAmount);
        market2.approve(address(ib), market2SupplyAmount);
        ib.supply(user, user, address(market2), market2SupplyAmount);

        /**
         * collateral value = 1000 * 0.8 * 1500 + 1000 * 0.8 * (0.5 * 3000) = 2,400,000
         * debt value = 0
         */
        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user);
        assertEq(collateralValue, 2400000e18);
        assertEq(debtValue, 0);

        uint256 market1BorrowAmount = 1000 * (10 ** underlyingDecimals1);
        ib.borrow(user, user, address(market1), market1BorrowAmount);

        /**
         * collateral value = 1000 * 0.8 * 1500 + 1000 * 0.8 * (0.5 * 3000) = 2,400,000
         * debt value = 1000 * 1500 = 1,500,000
         */
        (collateralValue, debtValue) = ib.getAccountLiquidity(user);
        assertEq(collateralValue, 2400000e18);
        assertEq(debtValue, 1500000e18);

        uint256 market2RedeemAmount = 500 * (10 ** underlyingDecimals2);
        ib.redeem(user, user, address(market2), market2RedeemAmount);

        /**
         * collateral value = 1000 * 0.8 * 1500 + 500 * 0.8 * (0.5 * 3000) = 1,800,000
         * debt value = 1000 * 1500 = 1,500,000
         */
        (collateralValue, debtValue) = ib.getAccountLiquidity(user);
        assertEq(collateralValue, 1800000e18);
        assertEq(debtValue, 1500000e18);
        vm.stopPrank();
    }

    function testGetAccountLiquidityWithTransferIBToken() public {
        uint256 market1SupplyAmount = 1000 * (10 ** underlyingDecimals1);
        uint256 market2SupplyAmount = 1000 * (10 ** underlyingDecimals2);

        vm.startPrank(user);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user, user, address(market1), market1SupplyAmount);
        market2.approve(address(ib), market2SupplyAmount);
        ib.supply(user, user, address(market2), market2SupplyAmount);

        /**
         * collateral value = 1000 * 0.8 * 1500 + 1000 * 0.8 * (0.5 * 3000) = 2,400,000
         * debt value = 0
         */
        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user);
        assertEq(collateralValue, 2400000e18);
        assertEq(debtValue, 0);

        uint256 market1BorrowAmount = 200 * (10 ** underlyingDecimals1);
        ib.borrow(user, user, address(market1), market1BorrowAmount);

        /**
         * collateral value = 1000 * 0.8 * 1500 + 1000 * 0.8 * (0.5 * 3000) = 2,400,000
         * debt value = 200 * 1500 = 300,000
         */
        (collateralValue, debtValue) = ib.getAccountLiquidity(user);
        assertEq(collateralValue, 2400000e18);
        assertEq(debtValue, 300000e18);

        uint256 balance = ibToken1.balanceOf(user);
        ibToken1.transfer(admin, balance);

        /**
         * collateral value = 1000 * 0.8 * (0.5 * 3000) = 1,200,000
         * debt value = 200 * 1500 = 300,000
         */
        (collateralValue, debtValue) = ib.getAccountLiquidity(user);
        assertEq(collateralValue, 1200000e18);
        assertEq(debtValue, 300000e18);
        vm.stopPrank();
    }

    function testGetAccountLiquidityWithDelisting() public {
        uint256 market1SupplyAmount = 1000 * (10 ** underlyingDecimals1);
        uint256 market2SupplyAmount = 1000 * (10 ** underlyingDecimals2);

        vm.startPrank(user);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user, user, address(market1), market1SupplyAmount);
        market2.approve(address(ib), market2SupplyAmount);
        ib.supply(user, user, address(market2), market2SupplyAmount);
        uint256 market1BorrowAmount = 1000 * (10 ** underlyingDecimals1);
        ib.borrow(user, user, address(market1), market1BorrowAmount);

        /**
         * collateral value = 1000 * 0.8 * 1500 + 1000 * 0.8 * (0.5 * 3000) = 2,400,000
         * debt value = 1000 * 1500 = 1,500,000
         */
        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user);
        assertEq(collateralValue, 2400000e18);
        assertEq(debtValue, 1500000e18);
        vm.stopPrank();

        vm.startPrank(admin);
        configurator.softDelistMarket(address(market2));
        configurator.adjustMarketCollateralFactor(address(market2), 0);
        configurator.adjustMarketLiquidationThreshold(address(market2), 0);
        configurator.hardDelistMarket(address(market2));

        /**
         * collateral value = 1000 * 0.8 * 1500 = 1,200,000
         * debt value = 1000 * 1500 = 1,500,000
         */
        (collateralValue, debtValue) = ib.getAccountLiquidity(user);
        assertEq(collateralValue, 1200000e18);
        assertEq(debtValue, 1500000e18);
        vm.stopPrank();
    }

    function testCannotGetAccountLiquidityForInvalidPrice() public {
        uint256 market1SupplyAmount = 1000 * (10 ** underlyingDecimals1);

        vm.startPrank(user);
        market1.approve(address(ib), market1SupplyAmount);
        ib.supply(user, user, address(market1), market1SupplyAmount);
        vm.stopPrank();

        MockPriceOracle mockOracle = new MockPriceOracle();
        mockOracle.setPrice(address(market1), 0);

        vm.prank(admin);
        ib.setPriceOracle(address(mockOracle));

        vm.expectRevert("invalid price");
        ib.getAccountLiquidity(user);
    }
}
