// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract SupplyTest is Test, Common {
    uint16 internal constant reserveFactor = 1000; // 10%

    int256 internal constant market1Price = 1500e8;
    int256 internal constant market2Price = 1500e8;
    uint16 internal constant market2CollateralFactor = 8000; // 80%

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

        configureMarketAsCollateral(admin, configurator, address(market2), market2CollateralFactor);

        deal(address(market1), user1, 10000e18);
        deal(address(market1), user2, 10000e18);
    }

    function testSupply() public {
        uint256 supplyAmount = 100e18;

        vm.startPrank(user1);
        market1.approve(address(ib), supplyAmount);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Supply(address(market1), user1, user1, supplyAmount, supplyAmount);

        ib.supply(user1, user1, address(market1), supplyAmount);
        vm.stopPrank();

        assertEq(ibToken1.balanceOf(user1), 100e18);
        assertEq(ibToken1.totalSupply(), 100e18);

        fastForwardTime(86400);

        // Accrue no interest without borrows.
        ib.accrueInterest(address(market1));
        assertEq(ibToken1.balanceOf(user1), 100e18);
        assertEq(ib.getSupplyBalance(user1, address(market1)), 100e18);
    }

    function testSupplyMultiple() public {
        uint256 supplyAmount = 100e18;

        vm.startPrank(user1);
        market1.approve(address(ib), type(uint256).max);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Supply(address(market1), user1, user1, supplyAmount, supplyAmount);

        ib.supply(user1, user1, address(market1), supplyAmount);
        vm.stopPrank();

        vm.startPrank(user2);
        market1.approve(address(ib), type(uint256).max);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Supply(address(market1), user2, user2, supplyAmount, supplyAmount);

        ib.supply(user2, user2, address(market1), supplyAmount);
        vm.stopPrank();

        vm.startPrank(user1);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Supply(address(market1), user1, user1, supplyAmount, supplyAmount);

        ib.supply(user1, user1, address(market1), supplyAmount);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Supply(address(market1), user1, user2, supplyAmount, supplyAmount);

        ib.supply(user1, user2, address(market1), supplyAmount); // supply for user2
        vm.stopPrank();

        assertEq(ibToken1.balanceOf(user1), 200e18);
        assertEq(ib.getSupplyBalance(user1, address(market1)), 200e18);
        assertEq(ibToken1.balanceOf(user2), 200e18);
        assertEq(ib.getSupplyBalance(user2, address(market1)), 200e18);
        assertEq(ibToken1.totalSupply(), 400e18);
        assertEq(ib.getTotalSupply(address(market1)), 400e18);
    }

    function testSupplyOnBehalf() public {
        uint256 supplyAmount = 100e18;

        vm.startPrank(user1);
        market1.approve(address(ib), supplyAmount);
        ib.setUserExtension(user2, true);
        vm.stopPrank();

        vm.prank(user2);

        vm.expectEmit(true, true, true, true, address(ib));
        emit Supply(address(market1), user1, user2, supplyAmount, supplyAmount);

        ib.supply(user1, user2, address(market1), supplyAmount);

        assertEq(ibToken1.balanceOf(user2), 100e18);
        assertEq(ibToken1.totalSupply(), 100e18);
        assertEq(ib.getSupplyBalance(user2, address(market1)), 100e18);
    }

    function testCannotSupplyForInsufficientAllowance() public {
        uint256 supplyAmount = 100e18;

        vm.prank(user1);
        vm.expectRevert("ERC20: insufficient allowance");
        ib.supply(user1, user1, address(market1), supplyAmount);
    }

    function testCannotSupplyForInsufficientBalance() public {
        uint256 supplyAmount = 10001e18;

        vm.startPrank(user1);
        market1.approve(address(ib), supplyAmount);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        ib.supply(user1, user1, address(market1), supplyAmount);
        vm.stopPrank();
    }

    function testCannotSupplyForUnauthorized() public {
        uint256 supplyAmount = 100e18;

        vm.prank(user2);
        vm.expectRevert("!authorized");
        ib.supply(user1, user1, address(market1), supplyAmount);
    }

    function testCannotSupplyForMarketNotListed() public {
        ERC20 invalidMarket = new ERC20("Token", "TOKEN");

        uint256 supplyAmount = 100e18;

        vm.prank(user1);
        vm.expectRevert("not listed");
        ib.supply(user1, user1, address(invalidMarket), supplyAmount);
    }

    function testCannotSupplyForMarketSupplyPaused() public {
        uint256 supplyAmount = 100e18;

        vm.prank(admin);
        configurator.setMarketSupplyPaused(address(market1), true);

        vm.prank(user1);
        vm.expectRevert("supply paused");
        ib.supply(user1, user1, address(market1), supplyAmount);
    }

    function testCannotSupplyToCreditAccount() public {
        uint256 supplyAmount = 100e18;

        vm.prank(admin);
        creditLimitManager.setCreditLimit(user1, address(market1), 1); // amount not important

        vm.prank(user1);
        vm.expectRevert("cannot supply to credit account");
        ib.supply(user1, user1, address(market1), supplyAmount);
    }

    function testCannotSupplyForSupplyCapReached() public {
        uint256 supplyAmount = 100e18;
        uint256 supplyCap = 10e18;

        vm.prank(admin);
        configurator.setMarketSupplyCaps(constructMarketCapArgument(address(market1), supplyCap));

        vm.prank(user1);
        vm.expectRevert("supply cap reached");
        ib.supply(user1, user1, address(market1), supplyAmount);
    }

    function testCannotSupplyForSupplyCapReached2() public {
        uint256 supplyCap = 10e18;
        uint256 supplyAmount = supplyCap - 1; // supply almost to cap

        vm.prank(admin);
        configurator.setMarketSupplyCaps(constructMarketCapArgument(address(market1), supplyCap));

        vm.startPrank(user1);
        market1.approve(address(ib), supplyAmount);
        ib.supply(user1, user1, address(market1), supplyAmount);
        vm.stopPrank();

        // Make some borrows.
        vm.startPrank(admin);
        market2.approve(address(ib), 10000e18);
        ib.supply(admin, admin, address(market2), 10000e18);
        ib.borrow(admin, admin, address(market1), 5e18);
        vm.stopPrank();

        fastForwardTime(86400);

        // The total supply in underlying is now greater than the supply cap.
        vm.prank(user1);
        vm.expectRevert("supply cap reached");
        ib.supply(user1, user1, address(market1), 1);
    }
}
