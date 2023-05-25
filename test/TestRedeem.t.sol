// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract RedeemTest is Test, Common {
    int256 internal constant market1Price = 1500e8;
    int256 internal constant market2Price = 1000e8;
    uint16 internal constant reserveFactor = 1000; // 10%
    uint16 internal constant collateralFactor = 8000; // 80%

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

        (market1, ibToken1,) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);
        (market2, ibToken2,) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);
        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.USD, market2Price);

        configureMarketAsCollateral(admin, configurator, address(market1), collateralFactor);
        configureMarketAsCollateral(admin, configurator, address(market2), collateralFactor);

        deal(address(market1), user1, 10000e18);
    }

    function testRedeem() public {
        uint256 supplyAmount = 100e18;
        uint256 redeemAmount = 50e18;

        vm.startPrank(user1);
        market1.approve(address(ib), supplyAmount);
        ib.supply(user1, user1, address(market1), supplyAmount);

        fastForwardTime(86400);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Redeem(address(market1), user1, user1, redeemAmount, redeemAmount);

        ib.redeem(user1, user1, address(market1), redeemAmount);
        vm.stopPrank();

        assertEq(market1.balanceOf(user1), 9950e18); // 10000 - 100 + 50
        assertEq(ibToken1.balanceOf(user1), 50e18);
        assertEq(ib.getSupplyBalance(user1, address(market1)), 50e18);
        assertEq(ibToken1.totalSupply(), 50e18);
    }

    function testRedeemToOther() public {
        uint256 supplyAmount = 100e18;
        uint256 redeemAmount = 50e18;

        vm.startPrank(user1);
        market1.approve(address(ib), supplyAmount);
        ib.supply(user1, user1, address(market1), supplyAmount);

        fastForwardTime(86400);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Redeem(address(market1), user1, user2, redeemAmount, redeemAmount);

        ib.redeem(user1, user2, address(market1), redeemAmount);
        vm.stopPrank();

        assertEq(market1.balanceOf(user1), 9900e18); // 10000 - 100
        assertEq(market1.balanceOf(user2), redeemAmount);
        assertEq(ibToken1.balanceOf(user1), 50e18);
        assertEq(ib.getSupplyBalance(user1, address(market1)), 50e18);
        assertEq(ibToken1.totalSupply(), 50e18);
    }

    function testRedeemOnBehalf() public {
        uint256 supplyAmount = 100e18;
        uint256 redeemAmount = 50e18;

        vm.startPrank(user1);
        market1.approve(address(ib), supplyAmount);
        ib.supply(user1, user1, address(market1), supplyAmount);
        ib.setUserExtension(user2, true);
        vm.stopPrank();

        fastForwardTime(86400);

        vm.prank(user2);
        vm.expectEmit(true, true, true, true, address(ib));
        emit Redeem(address(market1), user1, user1, redeemAmount, redeemAmount);

        ib.redeem(user1, user1, address(market1), redeemAmount);

        assertEq(market1.balanceOf(user1), 9950e18); // 10000 - 100 + 50
        assertEq(ibToken1.balanceOf(user1), 50e18);
        assertEq(ib.getSupplyBalance(user1, address(market1)), 50e18);
        assertEq(ibToken1.totalSupply(), 50e18);
    }

    function testRedeemWithInterests() public {
        uint256 supplyAmount = 100e18;
        uint256 redeemAmount = 50e18;

        vm.startPrank(user1);
        market1.approve(address(ib), supplyAmount);
        ib.supply(user1, user1, address(market1), supplyAmount);
        vm.stopPrank();

        vm.startPrank(admin);
        market2.approve(address(ib), 10000e18);
        ib.supply(admin, admin, address(market2), 10000e18);
        ib.borrow(admin, admin, address(market1), 30e18);
        vm.stopPrank();

        fastForwardTime(86400);

        vm.prank(user1);
        vm.expectEmit(true, true, true, true, address(ib));
        emit Redeem(address(market1), user1, user1, redeemAmount, 49.998483725983132345e18); // ibTokenAmount = 50 / 1.0000303264

        ib.redeem(user1, user1, address(market1), redeemAmount);

        /**
         * utilization = 30 / 100 = 30% < kink1 = 80%
         * borrow rate = 0.000000001 + 0.3 * 0.000000001 = 0.0000000013
         * borrow interest = 0.0000000013 * 86400 * 30 = 0.0033696
         * fee increased = 0.0033696 * 0.1 = 0.00033696
         *
         * new total borrow = 30.0033696
         * new total supply = 100 * 100.0033696 / (100.0033696 - 0.00033696) = 100.000336949781526145
         * new exchange rate = 100.0033696 / 100.000336949781526145 = 1.0000303264
         * user remaining ibToken amount = 100 - 50 / 1.0000303264 = 50.001516274016867655
         */
        assertEq(ibToken1.balanceOf(user1), 50.001516274016867655e18);
        assertEq(ib.getSupplyBalance(user1, address(market1)), 50.00303264e18);
        assertEq(ibToken1.totalSupply(), 50.001516274016867655e18);
        assertEq(market1.balanceOf(user1), 9950e18);

        // Admin repays the debt for user1 to redeem.
        vm.startPrank(admin);
        market1.approve(address(ib), type(uint256).max);
        ib.repay(admin, admin, address(market1), type(uint256).max);
        vm.stopPrank();

        fastForwardTime(86400);

        vm.prank(user1);
        vm.expectEmit(true, true, true, true, address(ib));
        emit Redeem(address(market1), user1, user1, 50.00303264e18, 50.001516274016867655e18);

        ib.redeem(user1, user1, address(market1), type(uint256).max);

        assertEq(ibToken1.balanceOf(user1), 0);
        assertEq(ib.getSupplyBalance(user1, address(market1)), 0);
        assertEq(ibToken1.totalSupply(), 0);
        assertGt(market1.balanceOf(user1), 10000e18);
    }

    function testCannotRedeemForUnauthorized() public {
        uint256 redeemAmount = 50e18;

        vm.prank(user1);
        vm.expectRevert("!authorized");
        ib.redeem(user2, user2, address(market1), redeemAmount);
    }

    function testCannotRedeemForMarketNotListed() public {
        ERC20 invalidMarket = new ERC20("Token", "TOKEN");

        uint256 redeemAmount = 50e18;

        vm.prank(user1);
        vm.expectRevert("not listed");
        ib.redeem(user1, user1, address(invalidMarket), redeemAmount);
    }

    function testCannotRedeemForInsufficientCash() public {
        uint256 supplyAmount = 100e18;
        uint256 redeemAmount = 60e18;

        vm.startPrank(user1);
        market1.approve(address(ib), supplyAmount);
        ib.supply(user1, user1, address(market1), supplyAmount);
        vm.stopPrank();

        vm.startPrank(admin);
        market2.approve(address(ib), 10000e18);
        ib.supply(admin, admin, address(market2), 10000e18);
        ib.borrow(admin, admin, address(market1), 50e18);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert("insufficient cash");
        ib.redeem(user1, user1, address(market1), redeemAmount);
    }

    function testCannotRedeemForInsufficientBalance() public {
        uint256 supplyAmount = 100e18;
        uint256 redeemAmount = 101e18;

        vm.startPrank(user1);
        market1.approve(address(ib), supplyAmount);
        ib.supply(user1, user1, address(market1), supplyAmount);

        vm.expectRevert("insufficient balance");
        ib.redeem(user1, user1, address(market1), redeemAmount);
    }

    function testCannotRedeemForInsufficientCollateral() public {
        uint256 supplyAmount = 100e18;
        uint256 redeemAmount = 20e18;

        vm.startPrank(admin);
        market2.approve(address(ib), 10000e18);
        ib.supply(admin, admin, address(market2), 10000e18);
        vm.stopPrank();

        vm.startPrank(user1);
        market1.approve(address(ib), supplyAmount);
        ib.supply(user1, user1, address(market1), supplyAmount);
        ib.borrow(user1, user1, address(market2), 100e18);
        vm.stopPrank();

        /**
         * collateral value = 100 * 0.8 * 1500 = 120,000
         * borrowed value = 100 * 1000 = 100,000
         */
        vm.prank(user1);
        vm.expectRevert("insufficient collateral");
        ib.redeem(user1, user1, address(market1), redeemAmount);
    }
}
