// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract DebtTokenTest is Test, Common {
    uint16 internal constant reserveFactor = 1000; // 10%
    int256 internal constant market1Price = 1e8;
    int256 internal constant market2Price = 1500e8;
    uint16 internal constant market2CollateralFactor = 8000; // 80%

    IronBank ib;
    MarketConfigurator configurator;
    FeedRegistry registry;
    PriceOracle oracle;

    ERC20Market market1;
    ERC20Market market2;
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

        TripleSlopeRateModel irm = createDefaultIRM();

        (market1,, debtToken1) = createAndListERC20Market(6, admin, ib, configurator, irm, reserveFactor);
        (market2,, debtToken2) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);
        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.USD, market2Price);

        configureMarketAsCollateral(admin, configurator, address(market2), market2CollateralFactor);

        deal(address(market2), user1, 10000e18);
        deal(address(market2), user2, 10000e18);
    }

    function testChangeImplementation() public {
        DebtToken newImpl = new DebtToken();

        vm.prank(admin);
        debtToken1.upgradeTo(address(newImpl));
    }

    function testCannotInitializeAgain() public {
        vm.prank(admin);
        vm.expectRevert("Initializable: contract is already initialized");
        debtToken1.initialize("Name", "SYMBOL", user1, address(ib), address(market1));
    }

    function testCannotChangeImplementationForNotOwner() public {
        DebtToken newImpl = new DebtToken();

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        debtToken1.upgradeTo(address(newImpl));
    }

    function testAsset() public {
        assertEq(address(market1), debtToken1.asset());
        assertEq(address(market2), debtToken2.asset());
    }

    function testName() public {
        assertEq(debtToken1.name(), "Iron Bank Debt Token");
        assertEq(debtToken2.name(), "Iron Bank Debt Token");
    }

    function testSymbol() public {
        assertEq(debtToken1.symbol(), "debtToken");
        assertEq(debtToken2.symbol(), "debtToken");
    }

    function testDecimals() public {
        assertEq(debtToken1.decimals(), 6);
        assertEq(debtToken2.decimals(), 18);
    }

    function testBalanceOf() public {
        prepareBorrow();

        uint256 market1BorrowAmount = 200e6;

        vm.prank(user1);
        ib.borrow(user1, user1, address(market1), market1BorrowAmount);

        assertEq(debtToken1.balanceOf(user1), market1BorrowAmount);

        fastForwardTime(86400);

        assertEq(debtToken1.balanceOf(user1), market1BorrowAmount); // not updated yet

        ib.accrueInterest(address(market1));

        /**
         * utilization = 200 / 10000 = 2% < kink1 = 80%
         * borrow rate = 0.000000001 + 0.02 * 0.000000001 = 0.00000000102
         * borrow interest = 0.00000000102 * 86400 * 200 = 0.0176256
         */
        assertEq(debtToken1.balanceOf(user1), 200.017625e6);

        market1BorrowAmount = 500e6;

        vm.prank(user2);
        ib.borrow(user2, user2, address(market1), market1BorrowAmount);

        assertEq(debtToken1.balanceOf(user2), market1BorrowAmount);

        fastForwardTime(86400);

        assertEq(debtToken1.balanceOf(user2), market1BorrowAmount); // not updated yet

        ib.accrueInterest(address(market1));

        /**
         * utilization = 700.017625 / 10000 ~= 7% < kink1 = 80%
         * borrow rate = 0.000000001 + 0.0700017625 * 0.000000001 = 0.0000000010700002
         * user1 borrow interest = 0.0000000010700002 * 86400 * 200.017625 = 0.018491
         * user2 borrow interest = 0.0000000010700002 * 86400 * 500 = 0.046224
         */
        assertEq(debtToken1.balanceOf(user1), 200.036116e6);
        assertEq(debtToken1.balanceOf(user2), 500.046224e6);
    }

    function testTotalSupply() public {
        prepareBorrow();

        uint256 market1BorrowAmount = 200e6;

        vm.prank(user1);
        ib.borrow(user1, user1, address(market1), market1BorrowAmount);

        assertEq(debtToken1.totalSupply(), market1BorrowAmount);

        fastForwardTime(86400);

        assertEq(debtToken1.totalSupply(), market1BorrowAmount); // not updated yet

        ib.accrueInterest(address(market1));

        /**
         * utilization = 200 / 10000 = 2% < kink1 = 80%
         * borrow rate = 0.000000001 + 0.02 * 0.000000001 = 0.00000000102
         * borrow interest = 0.00000000102 * 86400 * 200 = 0.0176256
         */
        assertEq(debtToken1.totalSupply(), 200.017625e6);

        market1BorrowAmount = 500e6;

        vm.prank(user2);
        ib.borrow(user2, user2, address(market1), market1BorrowAmount);

        assertEq(debtToken1.totalSupply(), 700.017625e6);

        fastForwardTime(86400);

        assertEq(debtToken1.totalSupply(), 700.017625e6); // not updated yet

        ib.accrueInterest(address(market1));

        /**
         * utilization = 700.017625 / 10000 ~= 7% < kink1 = 80%
         * borrow rate = 0.000000001 + 0.0700017625 * 0.000000001 = 0.0000000010700002
         * user1 borrow interest = 0.0000000010700002 * 86400 * 200.017625 = 0.018491
         * user2 borrow interest = 0.0000000010700002 * 86400 * 500 = 0.046224
         */
        assertEq(debtToken1.totalSupply(), 700.08234e6);
    }

    function testCannotCallUnsupportedFunctions() public {
        vm.expectRevert("unsupported");
        debtToken1.allowance(user1, user2);

        vm.expectRevert("unsupported");
        debtToken1.approve(user2, 1);

        vm.expectRevert("unsupported");
        debtToken1.increaseAllowance(user2, 1);

        vm.expectRevert("unsupported");
        debtToken1.decreaseAllowance(user2, 1);

        vm.expectRevert("unsupported");
        debtToken1.transfer(user2, 1);

        vm.expectRevert("unsupported");
        debtToken1.transferFrom(user2, user1, 1);
    }

    function prepareBorrow() internal {
        vm.startPrank(admin);
        market1.approve(address(ib), 10000e6);
        ib.supply(admin, admin, address(market1), 10000e6);
        vm.stopPrank();

        vm.startPrank(user1);
        market2.approve(address(ib), 10000e18);
        ib.supply(user1, user1, address(market2), 10000e18);
        vm.stopPrank();

        vm.startPrank(user2);
        market2.approve(address(ib), 10000e18);
        ib.supply(user2, user2, address(market2), 10000e18);
        vm.stopPrank();
    }
}
