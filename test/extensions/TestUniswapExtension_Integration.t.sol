// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/Test.sol";
import "../Common.t.sol";

interface StEthInterface {
    function submit(address _referral) external payable;
}

contract UniswapExtensionIntegrationTest is Test, Common {
    using SafeERC20 for IERC20;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address constant feedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;
    address constant uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant uniswapV2Factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    uint16 internal constant reserveFactor = 1000; // 10%
    uint16 internal constant stableCollateralFactor = 9000; // 90%
    uint16 internal constant wethCollateralFactor = 7000; // 70%
    uint16 internal constant wstethCollateralFactor = 7000; // 70%

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    PriceOracle oracle;
    UniswapExtension extension;

    PToken pDAI;

    address admin = address(64);
    address user1 = address(128);

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        uint256 forkId = vm.createFork(url);
        vm.selectFork(forkId);

        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);

        vm.prank(admin);
        ib.setMarketConfigurator(address(configurator));

        creditLimitManager = createCreditLimitManager(admin, ib);

        vm.prank(admin);
        ib.setCreditLimitManager(address(creditLimitManager));

        TripleSlopeRateModel irm = createDefaultIRM();

        // List WETH, DAI, USDT and WSTETH.
        createAndListERC20Market(WETH, admin, ib, configurator, irm, reserveFactor);
        createAndListERC20Market(DAI, admin, ib, configurator, irm, reserveFactor);
        createAndListERC20Market(USDT, admin, ib, configurator, irm, reserveFactor);
        createAndListERC20Market(WSTETH, admin, ib, configurator, irm, reserveFactor);

        // List pDAI.
        pDAI = createPToken(admin, DAI);
        IBToken ibToken = createIBToken(admin, address(ib), address(pDAI));

        vm.prank(admin);
        configurator.listPTokenMarket(address(pDAI), address(ibToken), address(irm), reserveFactor);

        // Setup price oracle.
        oracle = createPriceOracle(admin, feedRegistry);

        vm.prank(admin);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, admin, WETH, Denominations.ETH, Denominations.USD);
        setPriceForMarket(oracle, admin, DAI, DAI, Denominations.USD);
        setPriceForMarket(oracle, admin, USDT, USDT, Denominations.USD);
        setPriceForMarket(oracle, admin, address(pDAI), DAI, Denominations.USD);

        // Set collateral factors.
        configureMarketAsCollateral(admin, configurator, WETH, wethCollateralFactor);
        configureMarketAsCollateral(admin, configurator, DAI, stableCollateralFactor);
        configureMarketAsCollateral(admin, configurator, USDT, stableCollateralFactor);
        configureMarketAsCollateral(admin, configurator, WSTETH, wstethCollateralFactor);
        configureMarketAsCollateral(admin, configurator, address(pDAI), stableCollateralFactor);

        extension = createUniswapExtension(admin, ib, uniswapV3Factory, uniswapV2Factory, WETH, STETH, WSTETH);

        // Give some ether to user1.
        vm.deal(user1, 10000e18);

        // User1 converts some ether to stETH.
        vm.prank(user1);
        StEthInterface(STETH).submit{value: 1000e18}(address(0));

        // Give some tokens to admin.
        deal(WETH, admin, 10000e18);
        deal(WSTETH, admin, 10000e18);
        deal(DAI, admin, 10000000e18);
        deal(USDT, admin, 10000000e6);

        // Admin supplies some liquidity to Iron Bank.
        vm.startPrank(admin);
        IERC20(WETH).safeIncreaseAllowance(address(ib), 10000e18);
        ib.supply(admin, admin, WETH, 10000e18);
        IERC20(WSTETH).safeIncreaseAllowance(address(ib), 10000e18);
        ib.supply(admin, admin, WSTETH, 10000e18);
        IERC20(DAI).safeIncreaseAllowance(address(ib), 10000000e18);
        ib.supply(admin, admin, DAI, 10000000e18);
        IERC20(USDT).safeIncreaseAllowance(address(ib), 10000000e6);
        ib.supply(admin, admin, USDT, 10000000e6);
        vm.stopPrank();

        // User1 authorizes the extension.
        vm.prank(user1);
        ib.setUserExtension(address(extension), true);
    }

    function testSupplyEther() public {
        uint256 poolWethBefore = IERC20(WETH).balanceOf(address(ib));
        uint256 user1EthBefore = user1.balance;
        uint256 supplyAmount = 10e18;

        vm.prank(user1);
        UniswapExtension.Action[] memory actions = new UniswapExtension.Action[](1);
        actions[0] = UniswapExtension.Action({name: "ACTION_SUPPLY_NATIVE_TOKEN", data: bytes("")});
        extension.execute{value: supplyAmount}(actions);

        uint256 poolWethAfter = IERC20(WETH).balanceOf(address(ib));
        uint256 user1EthAfter = user1.balance;
        assertEq(poolWethAfter - poolWethBefore, supplyAmount);
        assertEq(user1EthBefore - user1EthAfter, supplyAmount);
    }

    function testSupplyStEth() public {
        uint256 poolWStEthBefore = IERC20(WSTETH).balanceOf(address(ib));
        uint256 supplyAmount = 10e18;
        uint256 wstEthSupplyAmount = WstEthInterface(WSTETH).getWstETHByStETH(supplyAmount);

        vm.startPrank(user1);
        IERC20(STETH).safeIncreaseAllowance(address(extension), type(uint256).max); // Approve extension.

        UniswapExtension.Action[] memory actions = new UniswapExtension.Action[](1);
        actions[0] = UniswapExtension.Action({name: "ACTION_SUPPLY_STETH", data: abi.encode(supplyAmount)});
        extension.execute(actions);
        vm.stopPrank();

        uint256 poolWStEthAfter = IERC20(WSTETH).balanceOf(address(ib));
        assertEq(poolWStEthAfter - poolWStEthBefore, wstEthSupplyAmount);
    }

    function testSupplyPToken() public {
        uint256 supplyAmount = 10000e18;

        // User1 needs to have DAI to supply to pDAI.
        deal(DAI, user1, supplyAmount);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(extension), type(uint256).max); // Approve extension.

        uint256 poolPDaiBefore = IERC20(pDAI).balanceOf(address(ib));
        uint256 user1DaiBefore = IERC20(DAI).balanceOf(user1);

        UniswapExtension.Action[] memory actions = new UniswapExtension.Action[](1);
        actions[0] =
            UniswapExtension.Action({name: "ACTION_SUPPLY_PTOKEN", data: abi.encode(address(pDAI), supplyAmount)});
        extension.execute(actions);

        uint256 poolPDaiAfter = IERC20(pDAI).balanceOf(address(ib));
        uint256 user1DaiAfter = IERC20(DAI).balanceOf(user1);
        assertEq(poolPDaiAfter - poolPDaiBefore, supplyAmount);
        assertEq(user1DaiBefore - user1DaiAfter, supplyAmount);
        vm.stopPrank();
    }

    function testLongWethAgainstDaiThruUniV3() public {
        /**
         * Long 100 WETH with additional 100,000 DAI collateral.
         * Path: WETH -> USDC -> DAI
         */
        uint256 supplyAmount = 100000e18;
        deal(DAI, user1, supplyAmount);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(ib), supplyAmount);

        uint256 longAmount = 100e18;
        address[] memory path = new address[](3);
        path[0] = WETH;
        path[1] = USDC;
        path[2] = DAI;
        uint24[] memory fees = new uint24[](2);
        fees[0] = 500; // 0.05%
        fees[1] = 100; // 0.01%
        uint256 deadline = block.timestamp + 1 hours;
        UniswapExtension.Action[] memory actions1 = new UniswapExtension.Action[](2);
        actions1[0] = UniswapExtension.Action({name: "ACTION_SUPPLY", data: abi.encode(DAI, supplyAmount)});
        actions1[1] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V3_EXACT_OUTPUT",
            data: abi.encode(
                WETH, longAmount, DAI, type(uint256).max, path, fees, bytes32("SUB_ACTION_OPEN_LONG_POSITION"), deadline
                )
        });
        extension.execute(actions1);

        assertTrue(ib.getSupplyBalance(user1, WETH) == longAmount);
        assertTrue(ib.getSupplyBalance(user1, DAI) == supplyAmount);
        assertTrue(ib.getBorrowBalance(user1, WETH) == 0);
        assertTrue(ib.getBorrowBalance(user1, DAI) > 0);

        UniswapExtension.Action[] memory actions2 = new UniswapExtension.Action[](1);
        actions2[0] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V3_EXACT_INPUT",
            data: abi.encode(
                WETH, type(uint256).max, DAI, 0, path, fees, bytes32("SUB_ACTION_CLOSE_LONG_POSITION"), deadline
                )
        });
        extension.execute(actions2);

        assertTrue(ib.getSupplyBalance(user1, WETH) == 0);
        assertTrue(ib.getSupplyBalance(user1, DAI) > 0);
        assertTrue(ib.getBorrowBalance(user1, WETH) == 0);
        assertTrue(ib.getBorrowBalance(user1, DAI) > 0);
        vm.stopPrank();
    }

    function testShortWethAgainstDaiThruUniV3() public {
        /**
         * Short 100 WETH with additional 100,000 DAI collateral.
         * Path: WETH -> USDC -> DAI
         */
        uint256 supplyAmount = 100000e18;
        deal(DAI, user1, supplyAmount);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(ib), supplyAmount);

        uint256 shortAmount = 100e18;
        address[] memory path = new address[](3);
        path[0] = WETH;
        path[1] = USDC;
        path[2] = DAI;
        uint24[] memory fees = new uint24[](2);
        fees[0] = 500; // 0.05%
        fees[1] = 100; // 0.01%
        uint256 deadline = block.timestamp + 1 hours;
        UniswapExtension.Action[] memory actions1 = new UniswapExtension.Action[](2);
        actions1[0] = UniswapExtension.Action({name: "ACTION_SUPPLY", data: abi.encode(DAI, supplyAmount)});
        actions1[1] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V3_EXACT_INPUT",
            data: abi.encode(WETH, shortAmount, DAI, 0, path, fees, bytes32("SUB_ACTION_OPEN_SHORT_POSITION"), deadline)
        });
        extension.execute(actions1);

        assertTrue(ib.getSupplyBalance(user1, WETH) == 0);
        assertTrue(ib.getSupplyBalance(user1, DAI) > supplyAmount);
        assertTrue(ib.getBorrowBalance(user1, WETH) == shortAmount);
        assertTrue(ib.getBorrowBalance(user1, DAI) == 0);

        UniswapExtension.Action[] memory actions2 = new UniswapExtension.Action[](1);
        actions2[0] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V3_EXACT_OUTPUT",
            data: abi.encode(
                WETH,
                type(uint256).max,
                DAI,
                type(uint256).max,
                path,
                fees,
                bytes32("SUB_ACTION_CLOSE_SHORT_POSITION"),
                deadline
                )
        });
        extension.execute(actions2);

        assertTrue(ib.getSupplyBalance(user1, WETH) == 0);
        assertTrue(ib.getSupplyBalance(user1, DAI) > 0);
        assertTrue(ib.getBorrowBalance(user1, WETH) == 0);
        assertTrue(ib.getBorrowBalance(user1, DAI) == 0);
        vm.stopPrank();
    }

    function testLongDaiAgainstUsdtThruUniV3() public {
        /**
         * Long 100,000 DAI with additional 50,000 USDT collateral.
         * Path: DAI -> USDC -> USDT
         */
        uint256 supplyAmount = 50000e6;
        deal(USDT, user1, supplyAmount);

        vm.startPrank(user1);
        IERC20(USDT).safeIncreaseAllowance(address(ib), supplyAmount);

        uint256 longAmount = 100000e18;
        address[] memory path = new address[](3);
        path[0] = DAI;
        path[1] = USDC;
        path[2] = USDT;
        uint24[] memory fees = new uint24[](2);
        fees[0] = 100; // 0.01%
        fees[1] = 100; // 0.01%
        uint256 deadline = block.timestamp + 1 hours;
        UniswapExtension.Action[] memory actions1 = new UniswapExtension.Action[](2);
        actions1[0] = UniswapExtension.Action({name: "ACTION_SUPPLY", data: abi.encode(USDT, supplyAmount)});
        actions1[1] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V3_EXACT_OUTPUT",
            data: abi.encode(
                DAI, longAmount, USDT, type(uint256).max, path, fees, bytes32("SUB_ACTION_OPEN_LONG_POSITION"), deadline
                )
        });
        extension.execute(actions1);

        assertTrue(ib.getSupplyBalance(user1, DAI) == longAmount);
        assertTrue(ib.getSupplyBalance(user1, USDT) == supplyAmount);
        assertTrue(ib.getBorrowBalance(user1, DAI) == 0);
        assertTrue(ib.getBorrowBalance(user1, USDT) > 0);

        UniswapExtension.Action[] memory actions2 = new UniswapExtension.Action[](1);
        actions2[0] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V3_EXACT_INPUT",
            data: abi.encode(
                DAI, type(uint256).max, USDT, 0, path, fees, bytes32("SUB_ACTION_CLOSE_LONG_POSITION"), deadline
                )
        });
        extension.execute(actions2);

        assertTrue(ib.getSupplyBalance(user1, DAI) == 0);
        assertTrue(ib.getSupplyBalance(user1, USDT) > 0);
        assertTrue(ib.getBorrowBalance(user1, DAI) == 0);
        assertTrue(ib.getBorrowBalance(user1, USDT) > 0);
        vm.stopPrank();
    }

    function testShortDaiAgainstUsdtThruUniV3() public {
        /**
         * Short 100,000 DAI with additional 50,000 USDT collateral.
         * Path: DAI -> USDC -> USDT
         */
        uint256 supplyAmount = 50000e6;
        deal(USDT, user1, supplyAmount);

        vm.startPrank(user1);
        IERC20(USDT).safeIncreaseAllowance(address(ib), supplyAmount);

        uint256 shortAmount = 100000e18;
        address[] memory path = new address[](3);
        path[0] = DAI;
        path[1] = USDC;
        path[2] = USDT;
        uint24[] memory fees = new uint24[](2);
        fees[0] = 100; // 0.01%
        fees[1] = 100; // 0.01%
        uint256 deadline = block.timestamp + 1 hours;
        UniswapExtension.Action[] memory actions1 = new UniswapExtension.Action[](2);
        actions1[0] = UniswapExtension.Action({name: "ACTION_SUPPLY", data: abi.encode(USDT, supplyAmount)});
        actions1[1] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V3_EXACT_INPUT",
            data: abi.encode(DAI, shortAmount, USDT, 0, path, fees, bytes32("SUB_ACTION_OPEN_SHORT_POSITION"), deadline)
        });
        extension.execute(actions1);

        assertTrue(ib.getSupplyBalance(user1, DAI) == 0);
        assertTrue(ib.getSupplyBalance(user1, USDT) > supplyAmount);
        assertTrue(ib.getBorrowBalance(user1, DAI) == shortAmount);
        assertTrue(ib.getBorrowBalance(user1, USDT) == 0);

        UniswapExtension.Action[] memory actions2 = new UniswapExtension.Action[](1);
        actions2[0] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V3_EXACT_OUTPUT",
            data: abi.encode(
                DAI,
                type(uint256).max,
                USDT,
                type(uint256).max,
                path,
                fees,
                bytes32("SUB_ACTION_CLOSE_SHORT_POSITION"),
                deadline
                )
        });
        extension.execute(actions2);

        assertTrue(ib.getSupplyBalance(user1, DAI) == 0);
        assertTrue(ib.getSupplyBalance(user1, USDT) > 0);
        assertTrue(ib.getBorrowBalance(user1, DAI) == 0);
        assertTrue(ib.getBorrowBalance(user1, USDT) == 0);
        vm.stopPrank();
    }

    function testSwapDebtThruUniV3() public {
        /**
         * Swap 100 DAI debt to USDT.
         * Path: DAI -> USDC -> USDT
         */
        prepareBorrow();

        uint256 borrowAmount = 100e18;

        vm.startPrank(user1);
        ib.borrow(user1, user1, DAI, borrowAmount);

        assertTrue(ib.getBorrowBalance(user1, DAI) == borrowAmount);
        assertTrue(ib.getBorrowBalance(user1, USDT) == 0);

        address[] memory path = new address[](3);
        path[0] = DAI;
        path[1] = USDC;
        path[2] = USDT;
        uint24[] memory fees = new uint24[](2);
        fees[0] = 100; // 0.01%
        fees[1] = 100; // 0.01%
        uint256 deadline = block.timestamp + 1 hours;
        UniswapExtension.Action[] memory actions = new UniswapExtension.Action[](1);
        actions[0] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V3_EXACT_OUTPUT",
            data: abi.encode(
                DAI, borrowAmount, USDT, type(uint256).max, path, fees, bytes32("SUB_ACTION_SWAP_DEBT"), deadline
                )
        });
        extension.execute(actions);

        assertTrue(ib.getBorrowBalance(user1, DAI) == 0);
        assertTrue(ib.getBorrowBalance(user1, USDT) > 0);
    }

    function testSwapCollateralThruUniV3() public {
        /**
         * Swap 100 DAI collateral to USDT.
         * Path: DAI -> USDC -> USDT
         */
        uint256 supplyAmount = 100e18;
        deal(DAI, user1, supplyAmount);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(ib), supplyAmount);
        ib.supply(user1, user1, DAI, supplyAmount);

        assertTrue(ib.getSupplyBalance(user1, DAI) == supplyAmount);
        assertTrue(ib.getSupplyBalance(user1, USDT) == 0);

        address[] memory path = new address[](3);
        path[0] = DAI;
        path[1] = USDC;
        path[2] = USDT;
        uint24[] memory fees = new uint24[](2);
        fees[0] = 100; // 0.01%
        fees[1] = 100; // 0.01%
        uint256 deadline = block.timestamp + 1 hours;
        UniswapExtension.Action[] memory actions = new UniswapExtension.Action[](1);
        actions[0] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V3_EXACT_INPUT",
            data: abi.encode(DAI, supplyAmount, USDT, 0, path, fees, bytes32("SUB_ACTION_SWAP_COLLATERAL"), deadline)
        });
        extension.execute(actions);

        assertTrue(ib.getSupplyBalance(user1, DAI) == 0);
        assertTrue(ib.getSupplyBalance(user1, USDT) > 0);
    }

    function testLongWethAgainstDaiThruUniV2() public {
        /**
         * Long 100 WETH with additional 100,000 DAI collateral.
         * Path: WETH -> USDC -> DAI
         */
        uint256 supplyAmount = 100000e18;
        deal(DAI, user1, supplyAmount);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(ib), supplyAmount);

        uint256 longAmount = 100e18;
        address[] memory path = new address[](3);
        path[0] = WETH;
        path[1] = USDC;
        path[2] = DAI;
        uint256 deadline = block.timestamp + 1 hours;
        UniswapExtension.Action[] memory actions1 = new UniswapExtension.Action[](2);
        actions1[0] = UniswapExtension.Action({name: "ACTION_SUPPLY", data: abi.encode(DAI, supplyAmount)});
        actions1[1] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V2_EXACT_OUTPUT",
            data: abi.encode(
                WETH, longAmount, DAI, type(uint256).max, path, bytes32("SUB_ACTION_OPEN_LONG_POSITION"), deadline
                )
        });
        extension.execute(actions1);

        assertTrue(ib.getSupplyBalance(user1, WETH) == longAmount);
        assertTrue(ib.getSupplyBalance(user1, DAI) == supplyAmount);
        assertTrue(ib.getBorrowBalance(user1, WETH) == 0);
        assertTrue(ib.getBorrowBalance(user1, DAI) > 0);

        UniswapExtension.Action[] memory actions2 = new UniswapExtension.Action[](1);
        actions2[0] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V2_EXACT_INPUT",
            data: abi.encode(WETH, type(uint256).max, DAI, 0, path, bytes32("SUB_ACTION_CLOSE_LONG_POSITION"), deadline)
        });
        extension.execute(actions2);

        assertTrue(ib.getSupplyBalance(user1, WETH) == 0);
        assertTrue(ib.getSupplyBalance(user1, DAI) > 0);
        assertTrue(ib.getBorrowBalance(user1, WETH) == 0);
        assertTrue(ib.getBorrowBalance(user1, DAI) > 0);
        vm.stopPrank();
    }

    function testShortWethAgainstDaiThruUniV2() public {
        /**
         * Short 100 WETH with additional 100,000 DAI collateral.
         * Path: WETH -> USDC -> DAI
         */
        uint256 supplyAmount = 100000e18;
        deal(DAI, user1, supplyAmount);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(ib), supplyAmount);

        uint256 shortAmount = 100e18;
        address[] memory path = new address[](3);
        path[0] = WETH;
        path[1] = USDC;
        path[2] = DAI;
        uint256 deadline = block.timestamp + 1 hours;
        UniswapExtension.Action[] memory actions1 = new UniswapExtension.Action[](2);
        actions1[0] = UniswapExtension.Action({name: "ACTION_SUPPLY", data: abi.encode(DAI, supplyAmount)});
        actions1[1] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V2_EXACT_INPUT",
            data: abi.encode(WETH, shortAmount, DAI, 0, path, bytes32("SUB_ACTION_OPEN_SHORT_POSITION"), deadline)
        });
        extension.execute(actions1);

        assertTrue(ib.getSupplyBalance(user1, WETH) == 0);
        assertTrue(ib.getSupplyBalance(user1, DAI) > supplyAmount);
        assertTrue(ib.getBorrowBalance(user1, WETH) == shortAmount);
        assertTrue(ib.getBorrowBalance(user1, DAI) == 0);

        UniswapExtension.Action[] memory actions2 = new UniswapExtension.Action[](1);
        actions2[0] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V2_EXACT_OUTPUT",
            data: abi.encode(
                WETH, type(uint256).max, DAI, type(uint256).max, path, bytes32("SUB_ACTION_CLOSE_SHORT_POSITION"), deadline
                )
        });
        extension.execute(actions2);

        assertTrue(ib.getSupplyBalance(user1, WETH) == 0);
        assertTrue(ib.getSupplyBalance(user1, DAI) > 0);
        assertTrue(ib.getBorrowBalance(user1, WETH) == 0);
        assertTrue(ib.getBorrowBalance(user1, DAI) == 0);
        vm.stopPrank();
    }

    function testLongDaiAgainstUsdtThruUniV2() public {
        /**
         * Long 100,000 DAI with additional 50,000 USDT collateral.
         * Path: DAI -> USDC -> USDT
         */
        uint256 supplyAmount = 50000e6;
        deal(USDT, user1, supplyAmount);

        vm.startPrank(user1);
        IERC20(USDT).safeIncreaseAllowance(address(ib), supplyAmount);

        uint256 longAmount = 100000e18;
        address[] memory path = new address[](3);
        path[0] = DAI;
        path[1] = USDC;
        path[2] = USDT;
        uint256 deadline = block.timestamp + 1 hours;
        UniswapExtension.Action[] memory actions1 = new UniswapExtension.Action[](2);
        actions1[0] = UniswapExtension.Action({name: "ACTION_SUPPLY", data: abi.encode(USDT, supplyAmount)});
        actions1[1] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V2_EXACT_OUTPUT",
            data: abi.encode(
                DAI, longAmount, USDT, type(uint256).max, path, bytes32("SUB_ACTION_OPEN_LONG_POSITION"), deadline
                )
        });
        extension.execute(actions1);

        assertTrue(ib.getSupplyBalance(user1, DAI) == longAmount);
        assertTrue(ib.getSupplyBalance(user1, USDT) == supplyAmount);
        assertTrue(ib.getBorrowBalance(user1, DAI) == 0);
        assertTrue(ib.getBorrowBalance(user1, USDT) > 0);

        UniswapExtension.Action[] memory actions2 = new UniswapExtension.Action[](1);
        actions2[0] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V2_EXACT_INPUT",
            data: abi.encode(DAI, type(uint256).max, USDT, 0, path, bytes32("SUB_ACTION_CLOSE_LONG_POSITION"), deadline)
        });
        extension.execute(actions2);

        assertTrue(ib.getSupplyBalance(user1, DAI) == 0);
        assertTrue(ib.getSupplyBalance(user1, USDT) > 0);
        assertTrue(ib.getBorrowBalance(user1, DAI) == 0);
        assertTrue(ib.getBorrowBalance(user1, USDT) > 0);
        vm.stopPrank();
    }

    function testShortDaiAgainstUsdtThruUniV2() public {
        /**
         * Short 100,000 DAI with additional 50,000 USDT collateral.
         * Path: DAI -> USDC -> USDT
         */
        uint256 supplyAmount = 50000e6;
        deal(USDT, user1, supplyAmount);

        vm.startPrank(user1);
        IERC20(USDT).safeIncreaseAllowance(address(ib), supplyAmount);

        uint256 shortAmount = 100000e18;
        address[] memory path = new address[](3);
        path[0] = DAI;
        path[1] = USDC;
        path[2] = USDT;
        uint256 deadline = block.timestamp + 1 hours;
        UniswapExtension.Action[] memory actions1 = new UniswapExtension.Action[](2);
        actions1[0] = UniswapExtension.Action({name: "ACTION_SUPPLY", data: abi.encode(USDT, supplyAmount)});
        actions1[1] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V2_EXACT_INPUT",
            data: abi.encode(DAI, shortAmount, USDT, 0, path, bytes32("SUB_ACTION_OPEN_SHORT_POSITION"), deadline)
        });
        extension.execute(actions1);

        assertTrue(ib.getSupplyBalance(user1, DAI) == 0);
        assertTrue(ib.getSupplyBalance(user1, USDT) > supplyAmount);
        assertTrue(ib.getBorrowBalance(user1, DAI) == shortAmount);
        assertTrue(ib.getBorrowBalance(user1, USDT) == 0);

        UniswapExtension.Action[] memory actions2 = new UniswapExtension.Action[](1);
        actions2[0] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V2_EXACT_OUTPUT",
            data: abi.encode(
                DAI, type(uint256).max, USDT, type(uint256).max, path, bytes32("SUB_ACTION_CLOSE_SHORT_POSITION"), deadline
                )
        });
        extension.execute(actions2);

        assertTrue(ib.getSupplyBalance(user1, DAI) == 0);
        assertTrue(ib.getSupplyBalance(user1, USDT) > 0);
        assertTrue(ib.getBorrowBalance(user1, DAI) == 0);
        assertTrue(ib.getBorrowBalance(user1, USDT) == 0);
        vm.stopPrank();
    }

    function testSwapDebtThruUniV2() public {
        /**
         * Swap 100 DAI debt to USDT.
         * Path: DAI -> USDC -> USDT
         */
        prepareBorrow();

        uint256 borrowAmount = 100e18;

        vm.startPrank(user1);
        ib.borrow(user1, user1, DAI, borrowAmount);

        assertTrue(ib.getBorrowBalance(user1, DAI) == borrowAmount);
        assertTrue(ib.getBorrowBalance(user1, USDT) == 0);

        address[] memory path = new address[](3);
        path[0] = DAI;
        path[1] = USDC;
        path[2] = USDT;
        uint256 deadline = block.timestamp + 1 hours;
        UniswapExtension.Action[] memory actions = new UniswapExtension.Action[](1);
        actions[0] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V2_EXACT_OUTPUT",
            data: abi.encode(DAI, borrowAmount, USDT, type(uint256).max, path, bytes32("SUB_ACTION_SWAP_DEBT"), deadline)
        });
        extension.execute(actions);

        assertTrue(ib.getBorrowBalance(user1, DAI) == 0);
        assertTrue(ib.getBorrowBalance(user1, USDT) > 0);
    }

    function testSwapCollateralThruUniV2() public {
        /**
         * Swap 100 DAI collateral to USDT.
         * Path: DAI -> USDC -> USDT
         */
        uint256 supplyAmount = 100e18;
        deal(DAI, user1, supplyAmount);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(ib), supplyAmount);
        ib.supply(user1, user1, DAI, supplyAmount);

        assertTrue(ib.getSupplyBalance(user1, DAI) == supplyAmount);
        assertTrue(ib.getSupplyBalance(user1, USDT) == 0);

        address[] memory path = new address[](3);
        path[0] = DAI;
        path[1] = USDC;
        path[2] = USDT;
        uint256 deadline = block.timestamp + 1 hours;
        UniswapExtension.Action[] memory actions = new UniswapExtension.Action[](1);
        actions[0] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V2_EXACT_INPUT",
            data: abi.encode(DAI, supplyAmount, USDT, 0, path, bytes32("SUB_ACTION_SWAP_COLLATERAL"), deadline)
        });
        extension.execute(actions);

        assertTrue(ib.getSupplyBalance(user1, DAI) == 0);
        assertTrue(ib.getSupplyBalance(user1, USDT) > 0);
    }

    function prepareBorrow() internal {
        // Make user1 have some collateral to borrow.
        deal(DAI, user1, 1000000e18);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(ib), 1000000e18);
        ib.supply(user1, user1, DAI, 1000000e18);
        vm.stopPrank();
    }
}
