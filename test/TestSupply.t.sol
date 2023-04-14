// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract SupplyTest is Test, Common {
    uint8 internal constant underlyingDecimals = 18; // 1e18
    uint16 internal constant reserveFactor = 1000; // 10%

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;

    ERC20Market market;
    IBToken ibToken;

    address admin = address(64);
    address user1 = address(128);
    address user2 = address(256);

    function setUp() public {
        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);
        ib.setMarketConfigurator(address(configurator));

        creditLimitManager = createCreditLimitManager(admin, ib);
        ib.setCreditLimitManager(address(creditLimitManager));

        TripleSlopeRateModel irm = createDefaultIRM();

        (market, ibToken,) = createAndListERC20Market(underlyingDecimals, admin, ib, configurator, irm, reserveFactor);

        vm.startPrank(admin);
        market.transfer(user1, 10_000 * (10 ** underlyingDecimals));
        market.transfer(user2, 10_000 * (10 ** underlyingDecimals));
        vm.stopPrank();
    }

    function testSupply() public {
        uint256 supplyAmount = 100 * (10 ** underlyingDecimals);

        vm.startPrank(user1);
        market.approve(address(ib), supplyAmount);

        ib.supply(user1, address(market), supplyAmount);

        assertEq(ibToken.balanceOf(user1), 100e18);
        assertEq(ibToken.totalSupply(), 100e18);

        fastForwardTime(86400);

        // Accrue no interest without borrows.
        ib.accrueInterest(address(market));
        assertEq(ibToken.balanceOf(user1), 100e18);
        assertEq(ib.getSupplyBalance(user1, address(market)), 100e18);
        assertTrue(ib.isEnteredMarket(user1, address(market)));
    }

    function testSupplyMultiple() public {
        uint256 supplyAmount = 100 * (10 ** underlyingDecimals);

        vm.startPrank(user1);
        market.approve(address(ib), type(uint256).max);
        ib.supply(user1, address(market), supplyAmount);
        vm.stopPrank();

        vm.startPrank(user2);
        market.approve(address(ib), type(uint256).max);
        ib.supply(user2, address(market), supplyAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        ib.supply(user1, address(market), supplyAmount);
        ib.supply(user2, address(market), supplyAmount); // supply for user2
        vm.stopPrank();

        assertEq(ibToken.balanceOf(user1), 200e18);
        assertEq(ib.getSupplyBalance(user1, address(market)), 200e18);
        assertTrue(ib.isEnteredMarket(user1, address(market)));
        assertEq(ibToken.balanceOf(user2), 200e18);
        assertEq(ib.getSupplyBalance(user2, address(market)), 200e18);
        assertTrue(ib.isEnteredMarket(user2, address(market)));
        assertEq(ibToken.totalSupply(), 400e18);
        (,, uint256 totalSupply,) = ib.getMarketStatus(address(market));
        assertEq(totalSupply, 400e18);
    }

    function testCannotSupplyForInsufficientAllowance() public {
        uint256 supplyAmount = 100 * (10 ** underlyingDecimals);

        vm.prank(user1);
        vm.expectRevert("ERC20: insufficient allowance");
        ib.supply(user1, address(market), supplyAmount);
    }

    function testCannotSupplyForInsufficientBalance() public {
        uint256 supplyAmount = 10_001 * (10 ** underlyingDecimals);

        vm.startPrank(user1);
        market.approve(address(ib), supplyAmount);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        ib.supply(user1, address(market), supplyAmount);
    }

    function testCannotSupplyForMarketNotListed() public {
        ERC20 invalidMarket = new ERC20("Token", "TOKEN");

        uint256 supplyAmount = 100 * (10 ** underlyingDecimals);

        vm.prank(user1);
        vm.expectRevert("not listed");
        ib.supply(user1, address(invalidMarket), supplyAmount);
    }

    function testCannotSupplyForMarketFrozen() public {
        uint256 supplyAmount = 100 * (10 ** underlyingDecimals);

        vm.prank(admin);
        configurator.freezeMarket(address(market), true);

        vm.prank(user1);
        vm.expectRevert("frozen");
        ib.supply(user1, address(market), supplyAmount);
    }

    function testCannotSupplyForMarketSupplyPaused() public {
        uint256 supplyAmount = 100 * (10 ** underlyingDecimals);

        vm.prank(admin);
        configurator.setSupplyPaused(address(market), true);

        vm.prank(user1);
        vm.expectRevert("supply paused");
        ib.supply(user1, address(market), supplyAmount);
    }

    function testCannotSupplyForCreditAccount() public {
        uint256 supplyAmount = 100 * (10 ** underlyingDecimals);

        vm.prank(admin);
        creditLimitManager.setCreditLimit(user1, address(market), 1); // amount not important

        vm.prank(user1);
        vm.expectRevert("credit account cannot supply");
        ib.supply(user1, address(market), supplyAmount);
    }

    function testCannotSupplyForSupplyCapReached() public {
        uint256 supplyAmount = 100 * (10 ** underlyingDecimals);
        uint256 supplyCap = 10 * (10 ** underlyingDecimals);

        vm.prank(admin);
        configurator.setMarketSupplyCaps(constructMarketCapArgument(address(market), supplyCap));

        vm.prank(user1);
        vm.expectRevert("supply cap reached");
        ib.supply(user1, address(market), supplyAmount);
    }
}
