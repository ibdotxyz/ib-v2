// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../Common.t.sol";

abstract contract FlashLoanTestEvents {
    event BorrowResult(address borrowMarket, uint256 borrowAmount, address initiator);
}

contract FlashLaonBorrower1 is IERC3156FlashBorrower, FlashLoanTestEvents {
    FlashLoan flashLoan;

    constructor(FlashLoan _flashLoan) {
        flashLoan = _flashLoan;
    }

    function execute(IERC3156FlashBorrower receiver, address borrowMarket, uint256 borrowAmount) external {
        flashLoan.flashLoan(receiver, borrowMarket, borrowAmount, bytes(""));
    }

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        returns (bytes32)
    {
        data; // Shh

        emit BorrowResult(token, amount, initiator);

        // Do nothing.
        IERC20(token).approve(address(flashLoan), amount + fee);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

contract FlashLaonBorrower2 is IERC3156FlashBorrower {
    FlashLoan flashLoan;

    constructor(FlashLoan _flashLoan) {
        flashLoan = _flashLoan;
    }

    function execute(IERC3156FlashBorrower receiver, address borrowMarket, uint256 borrowAmount) external {
        flashLoan.flashLoan(receiver, borrowMarket, borrowAmount, abi.encode(borrowMarket, borrowAmount));
    }

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        returns (bytes32)
    {
        initiator; // Shh
        data; // Shh

        // Do nothing.
        IERC20(token).approve(address(flashLoan), amount + fee);

        return bytes32(""); // invalid return value
    }
}

contract FlashLaonBorrower3 is IERC3156FlashBorrower {
    FlashLoan flashLoan;

    constructor(FlashLoan _flashLoan) {
        flashLoan = _flashLoan;
    }

    function execute(IERC3156FlashBorrower receiver, address borrowMarket, uint256 borrowAmount) external {
        flashLoan.flashLoan(receiver, borrowMarket, borrowAmount, abi.encode(borrowMarket, borrowAmount));
    }

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        returns (bytes32)
    {
        initiator; // Shh
        data; // Shh

        // Do nothing but approve less than `amount + fee` to cause revert.
        IERC20(token).approve(address(flashLoan), amount + fee - 1);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

contract FlashLaonBorrower4 is IERC3156FlashBorrower {
    FlashLoan flashLoan;

    constructor(FlashLoan _flashLoan) {
        flashLoan = _flashLoan;
    }

    function execute(IERC3156FlashBorrower receiver, address borrowMarket, uint256 borrowAmount) external {
        flashLoan.flashLoan(receiver, borrowMarket, borrowAmount, abi.encode(borrowMarket, borrowAmount));
    }

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        returns (bytes32)
    {
        initiator; // Shh
        data; // Shh

        // Transfer out token to cause revert.
        IERC20(token).transfer(address(256), amount + fee);
        IERC20(token).approve(address(flashLoan), amount + fee);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

contract FlashLaonBorrower5 is IERC3156FlashBorrower, FlashLoanTestEvents {
    FlashLoan flashLoan;

    constructor(FlashLoan _flashLoan) {
        flashLoan = _flashLoan;
    }

    function execute(
        IERC3156FlashBorrower[] calldata receivers,
        address[] calldata borrowMarkets,
        uint256[] calldata borrowAmounts
    ) external {
        flashLoan.flashLoan(
            receivers[0], borrowMarkets[0], borrowAmounts[0], abi.encode(receivers, borrowMarkets, borrowAmounts, 0)
        );
    }

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        returns (bytes32)
    {
        fee; // Shh

        emit BorrowResult(token, amount, initiator);

        (
            IERC3156FlashBorrower[] memory receivers,
            address[] memory borrowMarkets,
            uint256[] memory borrowAmounts,
            uint256 index
        ) = abi.decode(data, (IERC3156FlashBorrower[], address[], uint256[], uint256));

        IERC20(token).approve(address(flashLoan), type(uint256).max);

        // Do another flash loan.
        if (borrowMarkets.length > 0 && index < borrowMarkets.length - 1) {
            uint256 nextIndex = index + 1;
            flashLoan.flashLoan(
                receivers[nextIndex],
                borrowMarkets[nextIndex],
                borrowAmounts[nextIndex],
                abi.encode(receivers, borrowMarkets, borrowAmounts, nextIndex)
            );
        }

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

contract FlashLoanTest is Test, Common, FlashLoanTestEvents {
    uint16 internal constant reserveFactor = 1000; // 10%
    int256 internal constant market1Price = 500e8;
    int256 internal constant market2Price = 800e8;

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    FeedRegistry registry;
    PriceOracle oracle;
    FlashLoan flashLoan;

    ERC20Market market1;
    ERC20Market market2;

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

        (market1,,) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);
        (market2,,) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);

        registry = createRegistry();
        oracle = createPriceOracle(admin, address(registry));

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, registry, admin, address(market1), address(market1), Denominations.USD, market1Price);
        setPriceForMarket(oracle, registry, admin, address(market2), address(market2), Denominations.USD, market2Price);

        flashLoan = createFlashLoan(ib);

        // Injest some liquidity for borrow.
        vm.startPrank(admin);
        market1.approve(address(ib), 10000e18);
        ib.supply(admin, admin, address(market1), 10000e18);
        market2.approve(address(ib), 10000e18);
        ib.supply(admin, admin, address(market2), 10000e18);
        vm.stopPrank();
    }

    function testMaxFlashLoan() public {
        ERC20 notListedMarket = new ERC20("Token", "TOKEN");
        assertEq(flashLoan.maxFlashLoan(address(notListedMarket)), 0); // won't revert

        uint256 maxAmount = flashLoan.maxFlashLoan(address(market1));
        assertEq(maxAmount, 10000e18);

        // Make some borrow.
        vm.prank(admin);
        creditLimitManager.setCreditLimit(user1, address(market1), 10000e18);

        vm.prank(user1);
        ib.borrow(user1, user1, address(market1), 1000e18);

        // borrowCap > totalBorrow, gap > totalCash
        uint256 borrowCap = 20000e18;

        vm.prank(admin);
        configurator.setMarketBorrowCaps(constructMarketCapArgument(address(market1), borrowCap));

        maxAmount = flashLoan.maxFlashLoan(address(market1));
        assertEq(maxAmount, 9000e18);

        // borrowCap > totalBorrow, gap < totalCash
        borrowCap = 5000e18;

        vm.prank(admin);
        configurator.setMarketBorrowCaps(constructMarketCapArgument(address(market1), borrowCap));

        maxAmount = flashLoan.maxFlashLoan(address(market1));
        assertEq(maxAmount, 4000e18);

        // borrowCap <= totalBorrow
        borrowCap = 1000e18;

        vm.prank(admin);
        configurator.setMarketBorrowCaps(constructMarketCapArgument(address(market1), borrowCap));

        maxAmount = flashLoan.maxFlashLoan(address(market1));
        assertEq(maxAmount, 0);
    }

    function testFlashFee() public {
        uint256 borrowAmount = 100e18;

        uint256 fee = flashLoan.flashFee(address(market1), borrowAmount);
        assertEq(fee, 0); // no fee

        ERC20 notListedMarket = new ERC20("Token", "TOKEN");
        vm.expectRevert("token not listed");
        flashLoan.flashFee(address(notListedMarket), borrowAmount);
    }

    function testFlashLoan() public {
        FlashLaonBorrower1 example = new FlashLaonBorrower1(flashLoan);

        uint256 borrowAmount = 100e18;

        vm.expectEmit(false, false, false, true);
        emit BorrowResult(address(market1), borrowAmount, address(example));
        example.execute(IERC3156FlashBorrower(address(example)), address(market1), borrowAmount);

        // Flash loan again for testing token approval not breaking anything.
        vm.prank(user1);
        vm.expectEmit(false, false, false, true);
        emit BorrowResult(address(market1), borrowAmount, user1);
        flashLoan.flashLoan(IERC3156FlashBorrower(address(example)), address(market1), borrowAmount, bytes("")); // EOA initiator
    }

    function testFlashLoanWithMultipleTimes() public {
        // Borrow market1 twice with the same receiver.

        FlashLaonBorrower5 example = new FlashLaonBorrower5(flashLoan);

        uint256 borrowAmount1 = 100e18;
        uint256 borrowAmount2 = 200e18;

        IERC3156FlashBorrower[] memory receivers = new IERC3156FlashBorrower[](2);
        receivers[0] = IERC3156FlashBorrower(address(example));
        receivers[1] = IERC3156FlashBorrower(address(example));

        address[] memory borrowMarkets = new address[](2);
        borrowMarkets[0] = address(market1);
        borrowMarkets[1] = address(market1);

        uint256[] memory borrowAmounts = new uint256[](2);
        borrowAmounts[0] = borrowAmount1;
        borrowAmounts[1] = borrowAmount2;

        vm.expectEmit(false, false, false, true);
        emit BorrowResult(address(market1), borrowAmount1, address(example));
        vm.expectEmit(false, false, false, true);
        emit BorrowResult(address(market1), borrowAmount2, address(example));

        example.execute(receivers, borrowMarkets, borrowAmounts);
    }

    function testFlashLoanWithMultipleTokens() public {
        // Borrow market1 and market2 with the same receiver.

        FlashLaonBorrower5 example = new FlashLaonBorrower5(flashLoan);

        uint256 borrowAmount1 = 100e18;
        uint256 borrowAmount2 = 200e18;

        IERC3156FlashBorrower[] memory receivers = new IERC3156FlashBorrower[](2);
        receivers[0] = IERC3156FlashBorrower(address(example));
        receivers[1] = IERC3156FlashBorrower(address(example));

        address[] memory borrowMarkets = new address[](2);
        borrowMarkets[0] = address(market1);
        borrowMarkets[1] = address(market2);

        uint256[] memory borrowAmounts = new uint256[](2);
        borrowAmounts[0] = borrowAmount1;
        borrowAmounts[1] = borrowAmount2;

        vm.expectEmit(false, false, false, true);
        emit BorrowResult(address(market1), borrowAmount1, address(example));
        vm.expectEmit(false, false, false, true);
        emit BorrowResult(address(market2), borrowAmount2, address(example));

        example.execute(receivers, borrowMarkets, borrowAmounts);
    }

    function testFlashLoanWithMultipleTokensAndReceivers() public {
        // Borrow market1 and market2 with different receivers.

        FlashLaonBorrower5 example1 = new FlashLaonBorrower5(flashLoan);
        FlashLaonBorrower5 example2 = new FlashLaonBorrower5(flashLoan);

        uint256 borrowAmount1 = 100e18;
        uint256 borrowAmount2 = 200e18;

        IERC3156FlashBorrower[] memory receivers = new IERC3156FlashBorrower[](2);
        receivers[0] = IERC3156FlashBorrower(address(example1));
        receivers[1] = IERC3156FlashBorrower(address(example2));

        address[] memory borrowMarkets = new address[](2);
        borrowMarkets[0] = address(market1);
        borrowMarkets[1] = address(market2);

        uint256[] memory borrowAmounts = new uint256[](2);
        borrowAmounts[0] = borrowAmount1;
        borrowAmounts[1] = borrowAmount2;

        vm.expectEmit(false, false, false, true);
        emit BorrowResult(address(market1), borrowAmount1, address(example1));
        vm.expectEmit(false, false, false, true);
        emit BorrowResult(address(market2), borrowAmount2, address(example1));

        example1.execute(receivers, borrowMarkets, borrowAmounts);
    }

    function testCannotFlashLoanForTokenNotListed() public {
        ERC20 notListedMarket = new ERC20("Token", "TOKEN");

        FlashLaonBorrower1 example = new FlashLaonBorrower1(flashLoan);

        uint256 borrowAmount = 100e18;

        vm.expectRevert("token not listed");
        example.execute(IERC3156FlashBorrower(address(example)), address(notListedMarket), borrowAmount);
    }

    function testCannotFlashLoanForBorrowTooMuch() public {
        FlashLaonBorrower1 example = new FlashLaonBorrower1(flashLoan);

        uint256 borrowAmount = 10001e18;

        vm.expectRevert("insufficient cash");
        example.execute(IERC3156FlashBorrower(address(example)), address(market1), borrowAmount);
    }

    function testCannotFlashLoanForCallbackFailed() public {
        FlashLaonBorrower2 example = new FlashLaonBorrower2(flashLoan);

        uint256 borrowAmount = 100e18;

        vm.expectRevert("callback failed");
        example.execute(IERC3156FlashBorrower(address(example)), address(market1), borrowAmount);
    }

    function testCannotFlashLoanForRepayFailed() public {
        FlashLaonBorrower3 example = new FlashLaonBorrower3(flashLoan);

        uint256 borrowAmount = 100e18;

        vm.expectRevert("ERC20: insufficient allowance");
        example.execute(IERC3156FlashBorrower(address(example)), address(market1), borrowAmount);
    }

    function testCannotFlashLoanForRepayFailed2() public {
        FlashLaonBorrower4 example = new FlashLaonBorrower4(flashLoan);

        uint256 borrowAmount = 100e18;

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        example.execute(IERC3156FlashBorrower(address(example)), address(market1), borrowAmount);
    }

    function testCannotOnDeferredLiquidityCheckForUntrustedMessageSender() public {
        vm.expectRevert("untrusted message sender");
        flashLoan.onDeferredLiquidityCheck(bytes(""));
    }
}
