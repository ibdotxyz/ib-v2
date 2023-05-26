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

    event Transfer(address indexed from, address indexed to, uint256 value);

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

    function testTotalSupply() public {
        prepareTransfer();

        assertEq(ibToken.totalSupply(), 10000e18);
        assertEq(ibToken.totalSupply(), ib.getTotalSupply(address(market)));
    }

    function testBalanceOf() public {
        prepareTransfer();

        assertEq(ibToken.balanceOf(user1), 10000e18);
        assertEq(ibToken.balanceOf(user1), ib.getIBTokenBalance(user1, address(market)));
    }

    function testTransfer() public {
        prepareTransfer();

        uint256 transferAmount = 100e18;

        vm.prank(user1);
        vm.expectEmit(true, true, false, true, address(ibToken));
        emit Transfer(user1, user2, transferAmount);

        ibToken.transfer(user2, transferAmount);

        assertEq(ibToken.balanceOf(user2), transferAmount);
    }

    function testTransferFrom() public {
        prepareTransfer();

        uint256 transferAmount = 100e18;

        vm.prank(user1);
        ibToken.approve(user2, transferAmount);

        vm.prank(user2);
        vm.expectEmit(true, true, false, true, address(ibToken));
        emit Transfer(user1, user2, transferAmount);

        ibToken.transferFrom(user1, user2, transferAmount);

        assertEq(ibToken.balanceOf(user2), transferAmount);
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
        prepareTransfer();

        vm.prank(admin);
        configurator.setMarketTransferPaused(address(market), true);

        vm.prank(user1);
        vm.expectRevert("transfer paused");
        ibToken.transfer(user2, 100e18);
    }

    function testCannotTransferIBTokenForSelfTransfer() public {
        prepareTransfer();

        vm.prank(user1);
        vm.expectRevert("cannot self transfer");
        ibToken.transfer(user1, 100e18);
    }

    function testCannotTransferIBTokenForTransferToCreditAccount() public {
        prepareTransfer();

        vm.prank(admin);
        creditLimitManager.setCreditLimit(user2, address(market), 100e18);

        vm.prank(user1);
        vm.expectRevert("cannot transfer to credit account");
        ibToken.transfer(user2, 100e18);
    }

    function testCannotTransferFromTheZeroAddress() public {
        prepareTransfer();

        vm.prank(user1);
        vm.expectRevert("transfer from the zero address");
        ibToken.transferFrom(address(0), user2, 100e18);
    }

    function testCannotTransferToTheZeroAddress() public {
        prepareTransfer();

        vm.prank(user1);
        vm.expectRevert("transfer to the zero address");
        ibToken.transfer(address(0), 100e18);
    }

    function testCannotTransferWithZeroAmount() public {
        prepareTransfer();

        vm.prank(user1);
        vm.expectRevert("transfer zero amount");
        ibToken.transfer(user2, 0);
    }

    function testCannotTransferForTransferAmountExceedsBalance() public {
        prepareTransfer();

        vm.prank(user1);
        vm.expectRevert("transfer amount exceeds balance");
        ibToken.transfer(user2, 10001e18);
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

    function testMint() public {
        address fakeIB = address(512);

        IBToken impl = new IBToken();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        IBToken ibToken2 = IBToken(address(proxy));
        ibToken2.initialize("Iron Bank Token", "ibToken", admin, fakeIB, address(market));

        uint256 mintAmount = 100e18;

        vm.prank(fakeIB);
        vm.expectEmit(true, true, false, true, address(ibToken2));
        emit Transfer(address(0), user1, mintAmount);

        ibToken2.mint(user1, mintAmount);
    }

    function testCannotMintForUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert("!authorized");
        ibToken.mint(user1, 100e18);
    }

    function testBurn() public {
        address fakeIB = address(512);

        IBToken impl = new IBToken();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        IBToken ibToken2 = IBToken(address(proxy));
        ibToken2.initialize("Iron Bank Token", "ibToken", admin, fakeIB, address(market));

        uint256 burnAmount = 100e18;

        vm.prank(fakeIB);
        vm.expectEmit(true, true, false, true, address(ibToken2));
        emit Transfer(user1, address(0), burnAmount);

        ibToken2.burn(user1, burnAmount);
    }

    function testCannotBurnForUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert("!authorized");
        ibToken.burn(user1, 100e18);
    }

    function testSeize() public {
        address fakeIB = address(512);

        IBToken impl = new IBToken();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        IBToken ibToken2 = IBToken(address(proxy));
        ibToken2.initialize("Iron Bank Token", "ibToken", admin, fakeIB, address(market));

        uint256 seizeAmount = 100e18;

        vm.prank(fakeIB);
        vm.expectEmit(true, true, false, true, address(ibToken2));
        emit Transfer(user2, user1, seizeAmount);

        ibToken2.seize(user2, user1, seizeAmount);
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
