// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract IBTokenTest is Test, Common {
    uint16 internal constant reserveFactor = 1000; // 10%
    uint16 internal constant collateralFactor = 5000; // 50%

    int256 internal constant marketPrice = 1500e8;

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    FeedRegistry registry;
    PriceOracle oracle;

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

        (market, ibToken,) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market), address(market), Denominations.USD, marketPrice);

        configureMarketAsCollateral(admin, configurator, address(market), collateralFactor);

        vm.prank(admin);
        market.transfer(user1, 10000e18);
    }

    function testAsset() public {
        assertEq(address(market), ibToken.asset());
    }

    function testTransfer() public {
        prepareTransfer();

        vm.prank(user1);
        ibToken.transfer(user2, 100e18);

        assertEq(ibToken.balanceOf(user2), 100e18);
    }

    function testTransferWithZeroAmount() public {
        prepareTransfer();

        vm.prank(user1);
        ibToken.transfer(user2, 0);

        assertEq(ibToken.balanceOf(user2), 0);
    }

    function testTransferFrom() public {
        prepareTransfer();

        vm.prank(user1);
        ibToken.approve(user2, 100e18);

        vm.prank(user2);
        ibToken.transferFrom(user1, user2, 100e18);

        assertEq(ibToken.balanceOf(user2), 100e18);
    }

    function testTransferFromWithZeroAmount() public {
        prepareTransfer();

        vm.prank(user2);
        ibToken.transferFrom(user1, user2, 0);

        assertEq(ibToken.balanceOf(user2), 0);
    }

    function testCannotTransferIBTokenForUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert("!authorized");
        ib.transferIBToken(address(market), user1, user2, 100e18);
    }

    function testCannotTransferIBTokenForTransferPaused() public {
        vm.prank(admin);
        configurator.setMarketTransferPaused(address(market), true);

        vm.prank(user1);
        vm.expectRevert("transfer paused");
        ibToken.transfer(user2, 100e18);
    }

    function testCannotTransferIBTokenForSelfTransfer() public {
        vm.prank(user1);
        vm.expectRevert("cannot self transfer");
        ibToken.transfer(user1, 100e18);
    }

    function testCannotTransferIBTokenForTransferToCreditAccount() public {
        vm.prank(admin);
        creditLimitManager.setCreditLimit(user2, address(market), 100e18);

        vm.prank(user1);
        vm.expectRevert("cannot transfer to credit account");
        ibToken.transfer(user2, 100e18);
    }

    function testCannotTransferIBTokenForInsufficientCollateral() public {
        prepareTransfer();

        vm.startPrank(user1);
        ib.borrow(user1, user1, address(market), 5000e18); // CF 50%, max borrow half

        vm.expectRevert("insufficient collateral");
        ibToken.transfer(user2, 1);
        vm.stopPrank();
    }

    function testCannotTransferFromForInsufficientAllowance() public {
        prepareTransfer();

        vm.prank(user1);
        ibToken.approve(user2, 100e18);

        vm.prank(user2);
        vm.expectRevert("ERC20: insufficient allowance");
        ibToken.transferFrom(user1, user2, 101e18);
    }

    function testCannotMintForUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert("!authorized");
        ibToken.mint(user1, 100e18);
    }

    function testCannotBurnForUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert("!authorized");
        ibToken.burn(user1, 100e18);
    }

    function testCannotSeizeForUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert("!authorized");
        ibToken.seize(user2, user1, 100e18);
    }

    function prepareTransfer() public {
        vm.startPrank(user1);
        market.approve(address(ib), 10000e18);
        ib.supply(user1, user1, address(market), 10000e18);
        vm.stopPrank();
    }
}
