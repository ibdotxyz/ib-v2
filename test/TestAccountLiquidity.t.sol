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

    address admin = address(64);
    address user = address(128);

    function setUp() public {
        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);
        ib.setMarketConfigurator(address(configurator));

        creditLimitManager = createCreditLimitManager(admin, ib);
        ib.setCreditLimitManager(address(creditLimitManager));

        TripleSlopeRateModel irm = createDefaultIRM();

        (market1,,) = createAndListERC20Market(underlyingDecimals1, admin, ib, configurator, irm, reserveFactor);
        (market2,,) = createAndListERC20Market(underlyingDecimals2, admin, ib, configurator, irm, reserveFactor);

        setMarketCollateralFactor(admin, configurator, address(market1), collateralFactor);
        setMarketCollateralFactor(admin, configurator, address(market2), collateralFactor);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);
        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.ETH, market2Price);
        setPriceToRegistry(registry, admin, Denominations.ETH, Denominations.USD, ethUsdPrice);

        vm.startPrank(admin);
        market1.transfer(user, 10_000 * (10 ** underlyingDecimals1));
        market2.transfer(user, 10_000 * (10 ** underlyingDecimals2));
        vm.stopPrank();
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

    function testGetAccountLiquidity2() public {
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
}
