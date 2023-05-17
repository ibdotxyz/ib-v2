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

        vm.prank(admin);
        ib.setMarketConfigurator(address(configurator));

        creditLimitManager = createCreditLimitManager(admin, ib);

        vm.prank(admin);
        ib.setCreditLimitManager(address(creditLimitManager));

        TripleSlopeRateModel irm = createDefaultIRM();

        (market, ibToken,) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market), address(market), Denominations.USD, marketPrice);

        configureMarketAsCollateral(admin, configurator, address(market), collateralFactor);

        deal(address(market), user1, 10000e18);
    }

    function testChangeImplementation() public {
        IBToken newImpl = new IBToken();

        vm.prank(admin);
        ibToken.upgradeTo(address(newImpl));
    }

    function testCannotInitializeAgain() public {
        vm.prank(admin);
        vm.expectRevert("Initializable: contract is already initialized");
        ibToken.initialize("Name", "SYMBOL", user1, address(ib), address(market));
    }

    function testCannotChangeImplementationForNotOwner() public {
        IBToken newImpl = new IBToken();

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        ibToken.upgradeTo(address(newImpl));
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

    function testCannotTransferIBTokenForNotListed() public {
        ERC20 notListedMarket = new ERC20("Token", "TOKEN");

        vm.prank(user1);
        vm.expectRevert("not listed");
        ib.transferIBToken(address(notListedMarket), user1, user2, 100e18);
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

    function testCannotSeizeForSelfSeize() public {
        address fakeIB = address(512);

        IBToken impl = new IBToken();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        IBToken ibToken2 = IBToken(address(proxy));
        ibToken2.initialize("Iron Bank Token", "ibToken", admin, fakeIB, address(market));

        vm.prank(fakeIB);
        vm.expectRevert("cannot self seize");
        ibToken2.seize(user1, user1, 100e18);
    }

    function prepareTransfer() public {
        vm.startPrank(user1);
        market.approve(address(ib), 10000e18);
        ib.supply(user1, user1, address(market), 10000e18);
        vm.stopPrank();
    }
}
