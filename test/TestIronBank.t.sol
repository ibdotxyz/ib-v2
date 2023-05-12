// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract IronBankTest is Test, Common {
    IronBank ib;

    address admin = address(64);
    address user1 = address(128);

    function setUp() public {
        ib = createIronBank(admin);
    }

    function testAdmin() public {
        assertEq(ib.owner(), admin);
    }

    function testCannotInitializeAgain() public {
        vm.prank(admin);
        vm.expectRevert("Initializable: contract is already initialized");
        ib.initialize(user1);
    }

    function testCannotChangeImplementationForNotAdmin() public {
        IronBank newImpl = new IronBank();
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        ib.upgradeTo(address(newImpl));
    }

    function testChangeImplementation() public {
        IronBank newImpl = new IronBank();
        vm.prank(admin);
        IronBank(address(ib)).upgradeTo(address(newImpl));
    }

    function testSetPriceOracle() public {
        PriceOracle oracle = new PriceOracle(address(0), address(0), address(0));

        vm.prank(admin);
        vm.expectEmit(false, false, false, true, address(ib));
        emit PriceOracleSet(address(oracle));

        ib.setPriceOracle(address(oracle));
        assertEq(ib.priceOracle(), address(oracle));
    }

    function testCannotSetPriceOracleForNotOwner() public {
        PriceOracle oracle = new PriceOracle(address(0), address(0), address(0));

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

    function testListMarket() public {
        address configurator = address(256);

        vm.prank(admin);
        ib.setMarketConfigurator(configurator);

        ERC20 market = new ERC20("Token", "TOKEN");
        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        config.isListed = true;

        vm.prank(configurator);
        vm.expectEmit(true, false, false, true, address(ib));
        emit MarketListed(address(market), uint40(block.timestamp), config);

        ib.listMarket(address(market), config);
    }

    function testCannotListMarketForNotMarketConfigurator() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        DataTypes.MarketConfig memory emptyConfig = ib.getMarketConfiguration(address(market));

        vm.prank(admin);
        vm.expectRevert("!configurator");
        ib.listMarket(address(market), emptyConfig);
    }

    function testCannotListMarketForAlreadyListed() public {
        address configurator = address(256);

        vm.prank(admin);
        ib.setMarketConfigurator(configurator);

        ERC20 market = new ERC20("Token", "TOKEN");
        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        config.isListed = true;

        vm.prank(configurator);
        ib.listMarket(address(market), config);

        vm.prank(configurator);
        vm.expectRevert("already listed");
        ib.listMarket(address(market), config);
    }

    function testDelistMarket() public {
        address configurator = address(256);

        vm.prank(admin);
        ib.setMarketConfigurator(configurator);

        ERC20 market = new ERC20("Token", "TOKEN");
        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        config.isListed = true;

        vm.prank(configurator);
        ib.listMarket(address(market), config);

        vm.prank(configurator);
        vm.expectEmit(true, false, false, true, address(ib));
        emit MarketDelisted(address(market));

        ib.delistMarket(address(market));
    }

    function testCannotDelistMarketForNotMarketConfigurator() public {
        ERC20 market = new ERC20("Token", "TOKEN");

        vm.prank(admin);
        vm.expectRevert("!configurator");
        ib.delistMarket(address(market));
    }

    function testCannotDelistMarketForNotListed() public {
        address configurator = address(256);

        vm.prank(admin);
        ib.setMarketConfigurator(configurator);

        ERC20 market = new ERC20("Token", "TOKEN");

        vm.prank(configurator);
        vm.expectRevert("not listed");
        ib.delistMarket(address(market));
    }

    function testSetMarketConfiguration() public {
        address configurator = address(256);

        vm.prank(admin);
        ib.setMarketConfigurator(configurator);

        ERC20 market = new ERC20("Token", "TOKEN");
        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        config.isListed = true;

        vm.prank(configurator);
        ib.listMarket(address(market), config);

        config.reserveFactor = 1000; // 10%

        vm.prank(configurator);
        vm.expectEmit(true, false, false, true, address(ib));
        emit MarketConfigurationChanged(address(market), config);

        ib.setMarketConfiguration(address(market), config);
    }

    function testCannotSetMarketConfigurationForNotMarketConfigurator() public {
        ERC20 market = new ERC20("Token", "TOKEN");
        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));

        vm.prank(admin);
        vm.expectRevert("!configurator");
        ib.setMarketConfiguration(address(market), config);
    }

    function testCannotSetMarketConfigurationForNotListed() public {
        address configurator = address(256);

        vm.prank(admin);
        ib.setMarketConfigurator(configurator);

        ERC20 market = new ERC20("Token", "TOKEN");
        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));

        vm.prank(configurator);
        vm.expectRevert("not listed");
        ib.setMarketConfiguration(address(market), config);
    }

    function testSetCreditLimit() public {
        address configurator = address(256);

        vm.prank(admin);
        ib.setMarketConfigurator(configurator);

        ERC20 market = new ERC20("Token", "TOKEN");
        DataTypes.MarketConfig memory config = ib.getMarketConfiguration(address(market));
        config.isListed = true;

        vm.prank(configurator);
        ib.listMarket(address(market), config);

        address creditLimitManager = address(512);

        vm.prank(admin);
        ib.setCreditLimitManager(creditLimitManager);

        uint256 creditLimit = 100;

        vm.prank(creditLimitManager);
        vm.expectEmit(true, true, false, true, address(ib));
        emit CreditLimitChanged(user1, address(market), creditLimit);

        ib.setCreditLimit(user1, address(market), 100);
    }

    function testCannotSetCreditLimitForNotCreditLimitManager() public {
        ERC20 market = new ERC20("Token", "TOKEN");

        vm.prank(admin);
        vm.expectRevert("!manager");
        ib.setCreditLimit(user1, address(market), 100);
    }

    function testCannotSetCreditLimitForNotListed() public {
        address creditLimitManager = address(256);

        vm.prank(admin);
        ib.setCreditLimitManager(creditLimitManager);

        ERC20 market = new ERC20("Token", "TOKEN");

        vm.prank(creditLimitManager);
        vm.expectRevert("not listed");
        ib.setCreditLimit(user1, address(market), 100);
    }
}
