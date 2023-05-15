// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract PriceOracleTest is Test, Common {
    uint8 internal constant underlyingDecimals1 = 18; // 1e18
    uint8 internal constant underlyingDecimals2 = 8; // 1e8
    uint16 internal constant reserveFactor = 1000; // 10%

    uint256 internal constant stEthPerToken = 1.1e18;

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    FeedRegistry registry;
    PriceOracle oracle;

    ERC20Market market1;
    ERC20Market market2;
    ERC20Market steth;
    MockWstEth wsteth;

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

        (market1,,) = createAndListERC20Market(underlyingDecimals1, admin, ib, configurator, irm, reserveFactor);
        (market2,,) = createAndListERC20Market(underlyingDecimals2, admin, ib, configurator, irm, reserveFactor);

        steth = new ERC20Market("Lido staked ETH", "stETH", 18, admin);
        wsteth = new MockWstEth("Lido wrapped staked ETH", "wstETH", stEthPerToken);
        createAndListERC20Market(address(wsteth), admin, ib, configurator, irm, reserveFactor);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry), address(steth), address(wsteth));
    }

    function testGetPrice() public {
        // Registry's decimals is 8.
        int256 market1Price = 1500e8;

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);

        // The price from oracle is normalized by asset's decimals.
        uint256 price = oracle.getPrice(address(market1));
        assertEq(price, 1500e18); // 1500e18 * 1e18 / 1e18
    }

    function testGetPrice2() public {
        // Registry's decimals is 8.
        int256 market2Price = 1500e8;

        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.USD, market2Price);

        // The price from oracle is normalized by asset's decimals.
        uint256 price = oracle.getPrice(address(market2));
        assertEq(price, 1500e28); // 1500e18 * 1e18 / 1e8
    }

    function testGetPrice3() public {
        // Registry's decimals is 8.
        int256 market2Price = 0.5e8;
        int256 ethUsdPrice = 3000e8;

        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.ETH, market2Price);
        setPriceToRegistry(registry, admin, Denominations.ETH, Denominations.USD, ethUsdPrice);

        // The price from oracle is normalized by asset's decimals.
        uint256 price = oracle.getPrice(address(market2));
        assertEq(price, 1500e28); // 1500e18 * 1e18 / 1e8
    }

    function testGetWstEthPrice() public {
        // Registry's decimals is 8.
        int256 market1Price = 1500e8;

        setPriceToRegistry(registry, admin, address(steth), Denominations.USD, market1Price);

        // The price from oracle is normalized by asset's decimals.
        uint256 price = oracle.getPrice(address(wsteth));
        assertEq(price, 1650e18); // 1500e18 * 1.1 * 1e18 / 1e18
    }

    function testCannotGetPriceForInvalidPrice() public {
        // The price is not set.
        vm.expectRevert("invalid price");
        oracle.getPrice(address(market1));

        // Registry's decimals is 8.
        int256 market1Price = 1500e8;

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);

        // The price is set but it's 0.
        setPriceToRegistry(registry, admin, address(market1), Denominations.USD, 0);
        vm.expectRevert("invalid price");
        oracle.getPrice(address(market1));
    }

    function testSetAggregators() public {
        int256 market1Price = 1500e8;

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);

        (address base, address quote) = oracle.aggregators(address(market1));
        assertEq(base, address(market1));
        assertEq(quote, Denominations.USD);

        int256 market2Price = 30000e8;
        setPriceForMarket(oracle, registry, admin, address(market2), Denominations.BTC, Denominations.USD, market2Price); // e.g market2 == WBTC

        (base, quote) = oracle.aggregators(address(market2));
        assertEq(base, Denominations.BTC);
        assertEq(quote, Denominations.USD);

        // Clear the price.
        setPriceForMarket(oracle, admin, address(market1), address(0), address(0));

        (base, quote) = oracle.aggregators(address(market1));
        assertEq(base, address(0));
        assertEq(quote, address(0));
    }

    function testCannotSetAggregatorsForNotAdmin() public {
        vm.expectRevert("Ownable: caller is not the owner");
        PriceOracle.Aggregator[] memory aggrs = new PriceOracle.Aggregator[](1);
        aggrs[0] = PriceOracle.Aggregator({asset: address(market1), base: address(market1), quote: Denominations.USD});
        oracle._setAggregators(aggrs);
    }

    function testCannotSetAggregatorsForUnsupportedQuote() public {
        vm.expectRevert("unsupported quote");
        vm.prank(admin);
        PriceOracle.Aggregator[] memory aggrs = new PriceOracle.Aggregator[](1);
        aggrs[0] = PriceOracle.Aggregator({asset: address(market1), base: address(market1), quote: Denominations.BTC});
        oracle._setAggregators(aggrs);
    }

    function testCannotSetAggregatorsForAggregatorNotEnabled() public {
        registry.setFeedDisabled(true);

        vm.expectRevert("aggregator not enabled");
        vm.prank(admin);
        PriceOracle.Aggregator[] memory aggrs = new PriceOracle.Aggregator[](1);
        aggrs[0] = PriceOracle.Aggregator({asset: address(market1), base: address(market1), quote: Denominations.USD});
        oracle._setAggregators(aggrs);
    }

    function testCannotSetAggregatorsForInvalidPrice() public {
        vm.expectRevert("invalid price");
        vm.prank(admin);
        PriceOracle.Aggregator[] memory aggrs = new PriceOracle.Aggregator[](1);
        aggrs[0] = PriceOracle.Aggregator({asset: address(market1), base: address(market1), quote: Denominations.USD});
        oracle._setAggregators(aggrs);
    }
}
