// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

interface RecipientInterface {
    /**
     * @dev Hook executed upon a transfer to the recipient
     */
    function tokensReceived() external;
}

contract ERC777Market is ERC20 {
    bool private attackSwitchOn;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function turnSwitchOn() external {
        attackSwitchOn = true;
    }

    function turnSwitchOff() external {
        attackSwitchOn = false;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        super.transfer(recipient, amount);
        if (attackSwitchOn) {
            RecipientInterface(recipient).tokensReceived();
        }
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        super.transferFrom(sender, recipient, amount);
        if (attackSwitchOn) {
            RecipientInterface(recipient).tokensReceived();
        }
        return true;
    }
}

contract MockERC777Recipient is RecipientInterface {
    using SafeERC20 for IERC20;

    IronBank ib;
    address supplyMarket;
    uint256 supplyAmount;
    address borrowMarket;
    uint256 borrowAmount;

    constructor(
        IronBank _ib,
        address _supplyMarket,
        uint256 _supplyAmount,
        address _borrowMarket,
        uint256 _borrowAmount
    ) {
        ib = _ib;
        supplyMarket = _supplyMarket;
        supplyAmount = _supplyAmount;
        borrowMarket = _borrowMarket;
        borrowAmount = _borrowAmount;
    }

    function tokensReceived() external {
        // Re-enter to borrow.
        ib.borrow(address(this), address(this), borrowMarket, borrowAmount);
    }

    function reentryBorrow() external {
        IERC20(supplyMarket).safeIncreaseAllowance(address(ib), supplyAmount);
        ib.supply(address(this), address(this), supplyMarket, supplyAmount);
        ib.borrow(address(this), address(this), borrowMarket, borrowAmount);
    }
}

contract ReEntryTest is Test, Common {
    uint16 internal constant reserveFactor = 1000; // 10%

    int256 internal constant market1Price = 1500e8;
    int256 internal constant market2Price = 1500e8;
    uint16 internal constant market1CollateralFactor = 8000; // 80%

    IronBank ib;
    MarketConfigurator configurator;
    FeedRegistry registry;
    PriceOracle oracle;

    ERC20Market market1;
    ERC777Market market2;

    address admin = address(64);

    function setUp() public {
        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);

        vm.prank(admin);
        ib.setMarketConfigurator(address(configurator));

        TripleSlopeRateModel irm = createDefaultIRM();

        (market1,,) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);

        // List a ERC777 market.
        market2 = new ERC777Market("Token", "TOKEN");
        IBToken ibToken = createIBToken(admin, address(ib), address(market2));
        DebtToken debtToken = createDebtToken(admin, address(ib), address(market2));

        vm.prank(admin);
        configurator.listMarket(address(market2), address(ibToken), address(debtToken), address(irm), reserveFactor);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);
        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.USD, market2Price);

        configureMarketAsCollateral(admin, configurator, address(market1), market1CollateralFactor);

        deal(address(market2), admin, 10000e18);

        // Inject some liquidity for borrow.
        vm.startPrank(admin);
        market2.approve(address(ib), 10000e18);
        ib.supply(admin, admin, address(market2), 10000e18);
        vm.stopPrank();
    }

    function testCannotReentryBorrow() public {
        uint256 market1SupplyAmount = 1000e18;
        uint256 market2BorrowAmount = 200e18;

        market2.turnSwitchOn();

        MockERC777Recipient borrower =
            new MockERC777Recipient(ib, address(market1), market1SupplyAmount, address(market2), market2BorrowAmount);
        deal(address(market1), address(borrower), market1SupplyAmount);

        vm.expectRevert("ReentrancyGuard: reentrant call");
        borrower.reentryBorrow();
    }
}
