// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract Example1 is DeferLiquidityCheckInterface {
    IronBank ib;

    constructor(IronBank _ib) {
        ib = _ib;
    }

    function execute(address supplyMarket, uint256 supplyAmount) external {
        ib.deferLiquidityCheck(msg.sender, abi.encode(msg.sender, supplyMarket, supplyAmount));
    }

    function onDeferredLiquidityCheck(bytes memory data) external override {
        (address user, address supplyMarket, uint256 supplyAmount) = abi.decode(data, (address, address, uint256));

        // Supplying doesn't need to defer liquidity check. It's just for testing.
        ib.supply(user, user, supplyMarket, supplyAmount);

        // Action supply won't check the liquidity so `liquidityCheckStatus` of the user won't be marked to dirty.
        // Therefore, in the end of the `deferLiquidityCheck` doesn't need to check the liquidity again.
    }
}

contract Example2 is DeferLiquidityCheckInterface {
    IronBank ib;

    constructor(IronBank _ib) {
        ib = _ib;
    }

    function execute(address borrowMarket, uint256 borrowAmount, address supplyMarket, uint256 supplyAmount) external {
        ib.deferLiquidityCheck(
            msg.sender, abi.encode(msg.sender, borrowMarket, borrowAmount, supplyMarket, supplyAmount)
        );
    }

    function onDeferredLiquidityCheck(bytes memory data) external override {
        (address user, address borrowMarket, uint256 borrowAmount, address supplyMarket, uint256 supplyAmount) =
            abi.decode(data, (address, address, uint256, address, uint256));

        // Without deferLiquidityCheck, borrowing will fail as the collateral is not enough at this point.
        ib.borrow(user, user, borrowMarket, borrowAmount);
        ib.supply(user, user, supplyMarket, supplyAmount);

        // Action borrow will check the liquidity so `liquidityCheckStatus` of the user will be marked to dirty.
        // Therefore, in the end of the `deferLiquidityCheck` it will check the liquidity again.
    }
}

contract Example3 is DeferLiquidityCheckInterface {
    IronBank ib;

    constructor(IronBank _ib) {
        ib = _ib;
    }

    function execute(address borrowMarket, uint256 borrowAmount, address supplyMarket, uint256 supplyAmount) external {
        ib.deferLiquidityCheck(
            msg.sender, abi.encode(msg.sender, borrowMarket, borrowAmount, supplyMarket, supplyAmount)
        );
    }

    function onDeferredLiquidityCheck(bytes memory data) external override {
        (address user, address borrowMarket, uint256 borrowAmount, address supplyMarket, uint256 supplyAmount) =
            abi.decode(data, (address, address, uint256, address, uint256));

        // Without deferLiquidityCheck, borrowing will fail as the collateral is not enough at this point.
        ib.borrow(user, user, borrowMarket, borrowAmount);
        ib.supply(user, user, supplyMarket, supplyAmount);
        ib.checkAccountLiquidity(user);

        // Action borrow and checkAccountLiquidity will check the liquidity so `liquidityCheckStatus` of the user will be marked to dirty.
        // Therefore, in the end of the `deferLiquidityCheck` it will check the liquidity again.
    }
}

contract Example4 is DeferLiquidityCheckInterface {
    IronBank ib;

    constructor(IronBank _ib) {
        ib = _ib;
    }

    function execute() external {
        ib.deferLiquidityCheck(msg.sender, abi.encode(msg.sender));
    }

    function onDeferredLiquidityCheck(bytes memory data) external override {
        (address user) = abi.decode(data, (address));

        // Re-enter to deferLiquidityCheck will revert.
        ib.deferLiquidityCheck(user, "");
    }
}

contract AccountLiquidityTest is Test, Common {
    uint16 internal constant reserveFactor = 1000; // 10%

    int256 internal constant market1Price = 1500e8;
    int256 internal constant market2Price = 200e8;
    uint16 internal constant market1CollateralFactor = 8000; // 80%

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    FeedRegistry registry;
    PriceOracle oracle;

    ERC20Market market1;
    ERC20Market market2;
    DebtToken debtToken1;
    DebtToken debtToken2;

    address admin = address(64);
    address user1 = address(128);

    function setUp() public {
        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);

        vm.prank(admin);
        ib.setMarketConfigurator(address(configurator));

        creditLimitManager = createCreditLimitManager(admin, ib);

        vm.prank(admin);
        ib.setCreditLimitManager(address(creditLimitManager));

        TripleSlopeRateModel irm = createDefaultIRM();

        (market1,, debtToken1) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);
        (market2,, debtToken2) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);
        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.USD, market2Price);

        configureMarketAsCollateral(admin, configurator, address(market1), market1CollateralFactor);

        deal(address(market1), user1, 10000e18);

        // Injest some liquidity for borrow.
        vm.startPrank(admin);
        market1.approve(address(ib), 10000e18);
        ib.supply(admin, admin, address(market1), 10000e18);
        market2.approve(address(ib), 10000e18);
        ib.supply(admin, admin, address(market2), 10000e18);
        vm.stopPrank();
    }

    function testCheckAccountLiquidity() public {
        ib.checkAccountLiquidity(user1);

        (uint256 collateralValue, uint256 debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 0);
        assertEq(debtValue, 0);

        uint256 supplyAmount = 100e18;

        vm.startPrank(user1);
        market1.approve(address(ib), supplyAmount);
        ib.supply(user1, user1, address(market1), supplyAmount);
        vm.stopPrank();

        ib.checkAccountLiquidity(user1);

        (collateralValue, debtValue) = ib.getAccountLiquidity(user1);
        assertEq(collateralValue, 120000e18); // 100 * 1500 * 0.8 = 120,000
        assertEq(debtValue, 0);
    }

    function testDeferLiquidityCheck1() public {
        Example1 example = new Example1(ib);

        uint256 supplyAmount = 100e18;

        vm.startPrank(user1);
        ib.setUserExtension(address(example), true);

        market1.approve(address(ib), supplyAmount);

        example.execute(address(market1), supplyAmount);
        vm.stopPrank();

        assertEq(ib.getSupplyBalance(user1, address(market1)), supplyAmount);
    }

    function testDeferLiquidityCheck2() public {
        Example2 example = new Example2(ib);

        uint256 borrowAmount = 500e18;
        uint256 supplyAmount = 100e18;

        vm.startPrank(user1);
        ib.setUserExtension(address(example), true);

        market1.approve(address(ib), supplyAmount);

        example.execute(address(market2), borrowAmount, address(market1), supplyAmount);
        vm.stopPrank();

        assertEq(ib.getSupplyBalance(user1, address(market1)), supplyAmount);
        assertEq(ib.getBorrowBalance(user1, address(market2)), borrowAmount);
    }

    function testDeferLiquidityCheck3() public {
        Example3 example = new Example3(ib);

        uint256 borrowAmount = 500e18;
        uint256 supplyAmount = 100e18;

        vm.startPrank(user1);
        ib.setUserExtension(address(example), true);

        market1.approve(address(ib), supplyAmount);

        example.execute(address(market2), borrowAmount, address(market1), supplyAmount);
        vm.stopPrank();

        assertEq(ib.getSupplyBalance(user1, address(market1)), supplyAmount);
        assertEq(ib.getBorrowBalance(user1, address(market2)), borrowAmount);
    }

    function testCannotDeferLiquidityCheckForNotImplementingCallback() public {
        vm.prank(user1);
        vm.expectRevert(bytes(""));
        ib.deferLiquidityCheck(user1, "");
    }

    function testCannotDeferLiquidityCheckForCreditAccount() public {
        vm.prank(admin);
        creditLimitManager.setCreditLimit(user1, address(market1), 100); // amount not important

        assertTrue(ib.isCreditAccount(user1));

        Example1 example = new Example1(ib);

        uint256 supplyAmount = 100e18;

        vm.startPrank(user1);
        ib.setUserExtension(address(example), true);

        vm.expectRevert("credit account cannot defer liquidity check");
        example.execute(address(market1), supplyAmount);
        vm.stopPrank();
    }

    function testCannotDeferLiquidityCheckForReentry() public {
        Example4 example = new Example4(ib);

        vm.prank(user1);
        vm.expectRevert("reentry defer liquidity check");
        example.execute();
    }

    function testCannotDeferLiquidityCheckForInsufficientCollateral() public {
        Example2 example = new Example2(ib);

        uint256 borrowAmount = 700e18; // 700 * 200 = 140,000
        uint256 supplyAmount = 100e18; // 100 * 1500 * 0.8 = 120,000

        vm.startPrank(user1);
        ib.setUserExtension(address(example), true);

        market1.approve(address(ib), supplyAmount);

        vm.expectRevert("insufficient collateral");
        example.execute(address(market2), borrowAmount, address(market1), supplyAmount);
        vm.stopPrank();
    }
}
