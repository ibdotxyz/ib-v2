// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract RepayTest is Test, Common {
    int256 internal constant market1Price = 1500e8;
    int256 internal constant market2Price = 1000e8;
    uint16 internal constant collateralFactor = 8000; // 80%

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
    address user2 = address(256);

    function setUp() public {
        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);

        vm.prank(admin);
        ib.setMarketConfigurator(address(configurator));

        creditLimitManager = createCreditLimitManager(admin, ib);

        vm.prank(admin);
        ib.setCreditLimitManager(address(creditLimitManager));

        TripleSlopeRateModel irm = createDefaultIRM();

        (market1,, debtToken1) = createAndListERC20Market(18, admin, ib, configurator, irm, 0);
        (market2,, debtToken2) = createAndListERC20Market(18, admin, ib, configurator, irm, 0);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);
        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.USD, market2Price);

        configureMarketAsCollateral(admin, configurator, address(market1), collateralFactor);
        configureMarketAsCollateral(admin, configurator, address(market2), collateralFactor);

        deal(address(market2), user1, 10000e18);
        deal(address(market1), user2, 10000e18);
    }

    function testRepay() public {
        uint256 borrowAmount = 300e18;
        uint256 repayAmount = 100e18;

        vm.startPrank(admin);
        market1.approve(address(ib), 500e18);
        ib.supply(admin, admin, address(market1), 500e18);
        vm.stopPrank();

        vm.startPrank(user1);
        market2.approve(address(ib), 10000e18);
        ib.supply(user1, user1, address(market2), 10000e18);
        ib.borrow(user1, user1, address(market1), borrowAmount);
        vm.stopPrank();

        fastForwardTime(86400);

        // User1 repays some.

        vm.startPrank(user1);
        market1.approve(address(ib), repayAmount);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Repay(address(market1), user1, user1, repayAmount, 200.041472e18, 200.041472e18);

        ib.repay(user1, user1, address(market1), repayAmount);
        vm.stopPrank();

        /**
         * total cash = 200
         * total borrow = 300
         * utilization = 300 / 500 = 60% < kink1 = 80%
         * borrow rate = 0.000000001 + 0.6 * 0.000000001 = 0.0000000016
         * borrow interest = 0.0000000016 * 86400 * 300 = 0.041472
         */
        assertEq(ib.getBorrowBalance(user1, address(market1)), 200.041472e18);
        assertEq(debtToken1.balanceOf(user1), 200.041472e18);
        assertEq(market1.balanceOf(user1), 200e18);

        fastForwardTime(86400);

        // User2 repays some for user1.

        vm.startPrank(user2);
        market1.approve(address(ib), repayAmount);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Repay(address(market1), user2, user1, repayAmount, 100.065669876518786214e18, 100.065669876518786242e18); // account borrow != total borrow

        ib.repay(user2, user1, address(market1), repayAmount);
        vm.stopPrank();

        /**
         * total cash = 300
         * total borrow = 200.041472
         * utilization = 200.041472 / 500.041472 ~= 40% < kink1 = 80%
         * borrow rate = 0.000000001 + 0.400049762272518068 * 0.000000001 = 0.000000001400049762
         * borrow interest = 0.000000001400049762 * 86400 * 200.041472 + 0.041472 = 0.065669876518786242
         *
         * User borrow is calculated by dividing borrow index. This will cause the total borrow to
         * be different from user1 borrow amount (the only borrower in this case).
         */
        assertGt(ib.getBorrowBalance(user1, address(market1)), 100.06566987e18);
        assertLt(ib.getBorrowBalance(user1, address(market1)), 100.06566988e18);
        assertGt(debtToken1.balanceOf(user1), 100.06566987e18);
        assertLt(debtToken1.balanceOf(user1), 100.06566988e18);
        assertEq(market1.balanceOf(user1), 200e18);

        fastForwardTime(86400);

        // User1 repays full.

        vm.startPrank(user1);
        market1.approve(address(ib), type(uint256).max);
        ib.setUserExtension(user2, true);
        vm.stopPrank();

        vm.prank(user2);
        vm.expectEmit(true, true, true, true, address(ib));
        emit Repay(address(market1), user1, user1, 100.076045593468789831e18, 0, 83); // total borrow not 0

        ib.repay(user1, user1, address(market1), type(uint256).max);

        assertEq(ib.getBorrowBalance(user1, address(market1)), 0);
        assertEq(debtToken1.balanceOf(user1), 0);
        assertLt(market1.balanceOf(user1), 100e18);

        // There is no borrower but the total borrow is still greater than 0.
        // The reason is the same as above.
        assertGt(ib.getTotalBorrow(address(market1)), 0);
    }

    function testRepayForCreditAccount() public {
        uint256 creditLimit = 100e18;

        vm.prank(admin);
        creditLimitManager.setCreditLimit(user1, address(market1), creditLimit);

        vm.startPrank(admin);
        market1.approve(address(ib), 500e18);
        ib.supply(admin, admin, address(market1), 500e18);
        vm.stopPrank();

        uint256 borrowAmount = 100e18;

        vm.startPrank(user1);
        ib.borrow(user1, user1, address(market1), borrowAmount);

        market1.approve(address(ib), borrowAmount);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Repay(address(market1), user1, user1, borrowAmount, 0, 0);

        ib.repay(user1, user1, address(market1), borrowAmount);
        vm.stopPrank();
    }

    function testCannotRepayForInsufficientAllowance() public {
        uint256 borrowAmount = 300e18;
        uint256 repayAmount = 100e18;

        vm.startPrank(admin);
        market1.approve(address(ib), 500e18);
        ib.supply(admin, admin, address(market1), 500e18);
        vm.stopPrank();

        vm.startPrank(user1);
        market2.approve(address(ib), 10000e18);
        ib.supply(user1, user1, address(market2), 10000e18);
        ib.borrow(user1, user1, address(market1), borrowAmount);

        vm.expectRevert("ERC20: insufficient allowance");
        ib.repay(user1, user1, address(market1), repayAmount);
    }

    function testCannotRepayForInsufficientBalance() public {
        uint256 borrowAmount = 300e18;
        uint256 repayAmount = 100e18;

        vm.startPrank(admin);
        market1.approve(address(ib), 500e18);
        ib.supply(admin, admin, address(market1), 500e18);
        vm.stopPrank();

        vm.startPrank(user1);
        market2.approve(address(ib), 10000e18);
        ib.supply(user1, user1, address(market2), 10000e18);
        ib.borrow(user1, user1, address(market1), borrowAmount);

        // Transfer out on purpose.
        market1.transfer(user2, borrowAmount);

        market1.approve(address(ib), repayAmount);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        ib.repay(user1, user1, address(market1), repayAmount);
        vm.stopPrank();
    }

    function testCannotRepayForUnauthorized() public {
        uint256 repayAmount = 50e18;

        vm.prank(user2);
        vm.expectRevert("!authorized");
        ib.repay(user1, user1, address(market1), repayAmount);
    }

    function testCannotRepayForMarketNotListed() public {
        ERC20 invalidMarket = new ERC20("Token", "TOKEN");

        uint256 repayAmount = 50e18;

        vm.prank(user1);
        vm.expectRevert("not listed");
        ib.repay(user1, user1, address(invalidMarket), repayAmount);
    }

    function testCannotRepayForCreditAccount() public {
        uint256 repayAmount = 50e18;

        vm.prank(admin);
        creditLimitManager.setCreditLimit(user1, address(market1), 1); // amount not important

        vm.prank(user2);
        vm.expectRevert("credit account can only repay for itself");
        ib.repay(user2, user1, address(market1), repayAmount);
    }

    function testCannotRepayForRepayTooMuch() public {
        uint256 borrowAmount = 300e18;
        uint256 repayAmount = 301e18;

        vm.startPrank(admin);
        market1.approve(address(ib), 500e18);
        ib.supply(admin, admin, address(market1), 500e18);
        vm.stopPrank();

        vm.startPrank(user1);
        market2.approve(address(ib), 10000e18);
        ib.supply(user1, user1, address(market2), 10000e18);
        ib.borrow(user1, user1, address(market1), borrowAmount);

        market1.approve(address(ib), repayAmount);

        vm.expectRevert("repay too much");
        ib.repay(user1, user1, address(market1), repayAmount);
        vm.stopPrank();
    }
}
