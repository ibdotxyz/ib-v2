// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/Test.sol";
import "../Common.t.sol";

interface StEthInterface {
    function submit(address _referral) external payable;
}

contract MigrationExtensionIntegrationTest is Test, Common {
    using SafeERC20 for IERC20;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant SUSHI = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;

    address constant ibWethV1 = 0x41c84c0e2EE0b740Cf0d31F63f3B6F627DC6b393;
    address constant ibDaiV1 = 0x8e595470Ed749b85C6F7669de83EAe304C2ec68F;
    address constant ibUsdtV1 = 0x48759F220ED983dB51fA7A8C0D2AAb8f3ce4166a;
    address constant ibWstEthV1 = 0xbC6B6c837560D1fE317eBb54E105C89f303d5AFd;
    address constant ibSushiV1 = 0x226F3738238932BA0dB2319a8117D9555446102f;

    address constant v1Comptroller = 0xAB1c342C7bf5Ec5F02ADEA1c2270670bCa144CbB;
    address constant feedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;

    uint16 internal constant reserveFactor = 1000; // 10%
    uint16 internal constant stableCollateralFactor = 9000; // 90%
    uint16 internal constant wethCollateralFactor = 7000; // 70%
    uint16 internal constant wstethCollateralFactor = 7000; // 70%

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    PriceOracle oracle;
    MigrationExtension extension;

    address admin = address(64);
    address user1 = address(128);

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        uint256 forkId = vm.createFork(url);
        vm.selectFork(forkId);

        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);

        vm.prank(admin);
        ib.setMarketConfigurator(address(configurator));

        creditLimitManager = createCreditLimitManager(admin, ib);

        vm.prank(admin);
        ib.setCreditLimitManager(address(creditLimitManager));

        TripleSlopeRateModel irm = createDefaultIRM();

        // List WETH, DAI, USDT and WSTETH.
        createAndListERC20Market(WETH, admin, ib, configurator, irm, reserveFactor);
        createAndListERC20Market(DAI, admin, ib, configurator, irm, reserveFactor);
        createAndListERC20Market(USDT, admin, ib, configurator, irm, reserveFactor);
        createAndListERC20Market(WSTETH, admin, ib, configurator, irm, reserveFactor);

        // Setup price oracle.
        oracle = createPriceOracle(admin, feedRegistry, STETH, WSTETH);

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, admin, WETH, Denominations.ETH, Denominations.USD);
        setPriceForMarket(oracle, admin, DAI, DAI, Denominations.USD);
        setPriceForMarket(oracle, admin, USDT, USDT, Denominations.USD);

        // Set collateral factors.
        configureMarketAsCollateral(admin, configurator, WETH, wethCollateralFactor);
        configureMarketAsCollateral(admin, configurator, DAI, stableCollateralFactor);
        configureMarketAsCollateral(admin, configurator, USDT, stableCollateralFactor);
        configureMarketAsCollateral(admin, configurator, WSTETH, wstethCollateralFactor);

        extension = createMigrationExtension(admin, ib, v1Comptroller, WETH);

        // Give some ether to user1.
        vm.deal(user1, 10000e18);

        // Give some tokens to admin.
        deal(WETH, admin, 10000e18);
        deal(WSTETH, admin, 10000e18);
        deal(DAI, admin, 10000000e18);
        deal(USDT, admin, 10000000e6);

        // Admin supplies some liquidity to Iron Bank.
        vm.startPrank(admin);
        IERC20(WETH).safeIncreaseAllowance(address(ib), 10000e18);
        ib.supply(admin, admin, WETH, 10000e18);
        IERC20(WSTETH).safeIncreaseAllowance(address(ib), 10000e18);
        ib.supply(admin, admin, WSTETH, 10000e18);
        IERC20(DAI).safeIncreaseAllowance(address(ib), 10000000e18);
        ib.supply(admin, admin, DAI, 10000000e18);
        IERC20(USDT).safeIncreaseAllowance(address(ib), 10000000e6);
        ib.supply(admin, admin, USDT, 10000000e6);
        vm.stopPrank();

        // User1 authorizes the extension.
        vm.prank(user1);
        ib.setUserExtension(address(extension), true);
    }

    function testMigrate() public {
        setUpUserPositionInV1();

        fastForwardTime(86400);

        vm.startPrank(user1);
        // User approves the extension to transfer their v1 tokens.
        IERC20(ibUsdtV1).safeApprove(address(extension), type(uint256).max);
        IERC20(ibWethV1).safeApprove(address(extension), type(uint256).max);
        IERC20(ibWstEthV1).safeApprove(address(extension), type(uint256).max);

        // User migrates their position to Iron Bank v2.
        address[] memory v1SupplyMarkets = new address[](3);
        v1SupplyMarkets[0] = ibUsdtV1;
        v1SupplyMarkets[1] = ibWethV1;
        v1SupplyMarkets[2] = ibWstEthV1;

        address[] memory v1BorrowMarkets = new address[](1);
        v1BorrowMarkets[0] = ibDaiV1;

        MigrationExtension.AdditionalSupply[] memory additionalSupplies = new MigrationExtension.AdditionalSupply[](0);

        extension.migrate(v1SupplyMarkets, v1BorrowMarkets, additionalSupplies);
        vm.stopPrank();

        assertEq(IERC20(ibUsdtV1).balanceOf(user1), 0);
        assertEq(IERC20(ibWethV1).balanceOf(user1), 0);
        assertEq(IERC20(ibWstEthV1).balanceOf(user1), 0);
        assertEq(IBTokenV1Interface(ibDaiV1).borrowBalanceStored(user1), 0);
    }

    function testMigrate2() public {
        setUpUserPositionInV1();

        fastForwardTime(86400);

        deal(WETH, user1, 10e18);

        vm.startPrank(user1);
        // User approves the extension to transfer their v1 tokens.
        IERC20(ibUsdtV1).safeApprove(address(extension), type(uint256).max);
        IERC20(WETH).safeApprove(address(ib), type(uint256).max);

        // User migrates their position to Iron Bank v2.
        address[] memory v1SupplyMarkets = new address[](1);
        v1SupplyMarkets[0] = ibUsdtV1;

        address[] memory v1BorrowMarkets = new address[](1);
        v1BorrowMarkets[0] = ibDaiV1;

        // Supply additional WETH.
        MigrationExtension.AdditionalSupply[] memory additionalSupplies = new MigrationExtension.AdditionalSupply[](1);
        additionalSupplies[0] = MigrationExtension.AdditionalSupply({market: WETH, amount: 10e18});

        extension.migrate(v1SupplyMarkets, v1BorrowMarkets, additionalSupplies);
        vm.stopPrank();

        assertEq(IERC20(ibUsdtV1).balanceOf(user1), 0);
        assertEq(IBTokenV1Interface(ibDaiV1).borrowBalanceStored(user1), 0);
    }

    function testMigrate3() public {
        setUpUserPositionInV1();

        fastForwardTime(86400);

        vm.startPrank(user1);
        // User approves the extension to transfer their v1 tokens.
        IERC20(ibUsdtV1).safeApprove(address(extension), type(uint256).max);

        // User migrates their position to Iron Bank v2.
        address[] memory v1SupplyMarkets = new address[](1);
        v1SupplyMarkets[0] = ibUsdtV1;

        address[] memory v1BorrowMarkets = new address[](1);
        v1BorrowMarkets[0] = ibDaiV1;

        // Supply additional ether.
        MigrationExtension.AdditionalSupply[] memory additionalSupplies = new MigrationExtension.AdditionalSupply[](1);
        additionalSupplies[0] =
            MigrationExtension.AdditionalSupply({market: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, amount: 0});

        extension.migrate{value: 10e18}(v1SupplyMarkets, v1BorrowMarkets, additionalSupplies);
        vm.stopPrank();

        assertEq(IERC20(ibUsdtV1).balanceOf(user1), 0);
        assertEq(IBTokenV1Interface(ibDaiV1).borrowBalanceStored(user1), 0);
    }

    function testCannotMigrateForMarketNotListedInV1() public {
        address lido = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;

        vm.startPrank(user1);
        // User approves the extension to transfer their v1 tokens.
        IERC20(lido).safeApprove(address(extension), type(uint256).max);

        // User migrates their position to Iron Bank v2.
        address[] memory v1SupplyMarkets = new address[](1);
        v1SupplyMarkets[0] = lido;

        address[] memory v1BorrowMarkets = new address[](0);

        MigrationExtension.AdditionalSupply[] memory additionalSupplies = new MigrationExtension.AdditionalSupply[](0);

        vm.expectRevert("market not listed in v1");
        extension.migrate(v1SupplyMarkets, v1BorrowMarkets, additionalSupplies);
        vm.stopPrank();
    }

    function testCannotMigrateForMarketNotListedInV2() public {
        setUpUserPositionInV1();

        fastForwardTime(86400);

        vm.startPrank(user1);
        // User approves the extension to transfer their v1 tokens.
        IERC20(ibSushiV1).safeApprove(address(extension), type(uint256).max);

        // User migrates their position to Iron Bank v2.
        address[] memory v1SupplyMarkets = new address[](1);
        v1SupplyMarkets[0] = ibSushiV1;

        address[] memory v1BorrowMarkets = new address[](0);

        MigrationExtension.AdditionalSupply[] memory additionalSupplies = new MigrationExtension.AdditionalSupply[](0);

        vm.expectRevert("not listed");
        extension.migrate(v1SupplyMarkets, v1BorrowMarkets, additionalSupplies);
        vm.stopPrank();
    }

    function testCannotMigrateForPaused() public {
        setUpUserPositionInV1();

        fastForwardTime(86400);

        vm.prank(admin);
        extension.pause();

        vm.startPrank(user1);
        // User approves the extension to transfer their v1 tokens.
        IERC20(ibUsdtV1).safeApprove(address(extension), type(uint256).max);

        // User migrates their position to Iron Bank v2.
        address[] memory v1SupplyMarkets = new address[](1);
        v1SupplyMarkets[0] = ibUsdtV1;

        address[] memory v1BorrowMarkets = new address[](0);

        MigrationExtension.AdditionalSupply[] memory additionalSupplies = new MigrationExtension.AdditionalSupply[](0);

        vm.expectRevert("Pausable: paused");
        extension.migrate(v1SupplyMarkets, v1BorrowMarkets, additionalSupplies);
        vm.stopPrank();
    }

    function testCannotMigrateForInsufficientCollateral() public {
        setUpUserPositionInV1();

        fastForwardTime(86400);

        vm.startPrank(user1);
        // User approves the extension to transfer their v1 tokens.
        IERC20(ibUsdtV1).safeApprove(address(extension), type(uint256).max);

        // User migrates their position to Iron Bank v2.
        address[] memory v1SupplyMarkets = new address[](1);
        v1SupplyMarkets[0] = ibUsdtV1;

        address[] memory v1BorrowMarkets = new address[](1);
        v1BorrowMarkets[0] = ibDaiV1;

        MigrationExtension.AdditionalSupply[] memory additionalSupplies = new MigrationExtension.AdditionalSupply[](0);

        vm.expectRevert("insufficient collateral");
        extension.migrate(v1SupplyMarkets, v1BorrowMarkets, additionalSupplies);
        vm.stopPrank();
    }

    function setUpUserPositionInV1() internal {
        /**
         * Supply: 10,000 USDT (90% CF), 10 WETH (85% CF), 5 WSTETH (70% CF), 50,000 SUSHI (70% CF)
         * Borrow: 10,000 DAI
         */
        deal(USDT, user1, 10000e6);
        deal(WETH, user1, 10e18);
        deal(WSTETH, user1, 5e18);
        deal(SUSHI, user1, 50000e18);

        vm.startPrank(user1);
        // User supplies some tokens to Iron Bank v1.
        IERC20(USDT).safeIncreaseAllowance(ibUsdtV1, 10000e6);
        IBTokenV1Interface(ibUsdtV1).mint(10000e6);
        IERC20(WETH).safeIncreaseAllowance(ibWethV1, 10e18);
        IBTokenV1Interface(ibWethV1).mint(10e18);
        IERC20(WSTETH).safeIncreaseAllowance(ibWstEthV1, 5e18);
        IBTokenV1Interface(ibWstEthV1).mint(5e18);
        IERC20(SUSHI).safeIncreaseAllowance(ibSushiV1, 50000e18);
        IBTokenV1Interface(ibSushiV1).mint(50000e18);

        // Enter markets.
        address[] memory markets = new address[](4);
        markets[0] = ibUsdtV1;
        markets[1] = ibWethV1;
        markets[2] = ibWstEthV1;
        markets[3] = ibSushiV1;
        ComptrollerV1Interface(v1Comptroller).enterMarkets(markets);

        // Borrow DAI.
        IBTokenV1Interface(ibDaiV1).borrow(10000e18);
        vm.stopPrank();
    }
}
