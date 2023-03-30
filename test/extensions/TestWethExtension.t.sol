// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/Test.sol";
import "../Common.t.sol";

contract WethExtensionTest is Test, Common {
    using SafeERC20 for IERC20;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address constant wethHolder = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e; // Aave aWETH
    address constant daiHolder = 0x028171bCA77440897B824Ca71D1c56caC55b68A3; // Aave aDAI

    address constant feedRegistry = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;

    uint16 internal constant reserveFactor = 1000; // 10%
    uint16 internal constant stableCollateralFactor = 9000; // 90%
    uint16 internal constant wethCollateralFactor = 7000; // 70%

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    ExtensionRegistry extensionRegistry;
    PriceOracle oracle;
    WethExtension wethExtension;

    address admin = address(64);
    address user1 = address(128);

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        uint256 forkId = vm.createFork(url);
        vm.selectFork(forkId);

        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);
        ib.setMarketConfigurator(address(configurator));

        creditLimitManager = createCreditLimitManager(admin, ib);
        ib.setCreditLimitManager(address(creditLimitManager));

        extensionRegistry = createExtensionRegistry(admin, ib);
        ib.setExtensionRegistry(address(extensionRegistry));

        TripleSlopeRateModel irm = createDefaultIRM();

        createAndListERC20Market(WETH, admin, ib, configurator, irm, reserveFactor);
        createAndListERC20Market(DAI, admin, ib, configurator, irm, reserveFactor);

        oracle = createPriceOracle(admin, feedRegistry);
        ib.setPriceOracle(address(oracle));

        setPriceForMarket(oracle, admin, WETH, Denominations.ETH, Denominations.USD);
        setPriceForMarket(oracle, admin, DAI, DAI, Denominations.USD);

        setMarketCollateralFactor(admin, configurator, WETH, wethCollateralFactor);
        setMarketCollateralFactor(admin, configurator, DAI, stableCollateralFactor);

        // Inject liquidity into pool.
        vm.startPrank(wethHolder);
        IERC20(WETH).safeIncreaseAllowance(address(ib), 10000e18);
        ib.supply(wethHolder, WETH, 10000e18);
        vm.stopPrank();

        vm.startPrank(daiHolder);
        IERC20(DAI).safeIncreaseAllowance(address(ib), 10000000e18);
        ib.supply(daiHolder, DAI, 10000000e18);
        vm.stopPrank();

        wethExtension = createWethExtension(admin, ib, extensionRegistry, WETH);
    }

    function testSupplyEther() public {
        uint256 poolWethBefore = IERC20(WETH).balanceOf(address(ib));
        uint256 supplyAmount = 10e18;

        vm.prank(user1);
        vm.deal(user1, supplyAmount);
        wethExtension.supplyNativeToken{value: supplyAmount}();

        uint256 poolWethAfter = IERC20(WETH).balanceOf(address(ib));
        assertEq(poolWethAfter - poolWethBefore, supplyAmount);
    }

    function testBorrowEther() public {
        prepareBorrow();

        uint256 poolWethBefore = IERC20(WETH).balanceOf(address(ib));
        uint256 borrowAmount = 10e18;

        vm.prank(user1);
        wethExtension.borrowNativeToken(borrowAmount);

        uint256 poolWethAfter = IERC20(WETH).balanceOf(address(ib));
        assertEq(poolWethBefore - poolWethAfter, borrowAmount);
    }

    function testRedeemEther() public {
        uint256 supplyAmount = 10e18;

        vm.prank(user1);
        vm.deal(user1, supplyAmount);
        wethExtension.supplyNativeToken{value: supplyAmount}();

        uint256 poolWethBefore = IERC20(WETH).balanceOf(address(ib));

        vm.prank(user1);
        wethExtension.redeemNativeToken(supplyAmount);

        uint256 poolWethAfter = IERC20(WETH).balanceOf(address(ib));
        assertEq(poolWethBefore - poolWethAfter, supplyAmount);
    }

    function testRepayEther() public {
        prepareBorrow();

        uint256 borrowAmount = 10e18;

        vm.prank(user1);
        wethExtension.borrowNativeToken(borrowAmount);

        uint256 poolWethBefore = IERC20(WETH).balanceOf(address(ib));
        uint256 repayAmount = 5e18;

        vm.prank(user1);
        wethExtension.repayNativeToken{value: repayAmount}();

        uint256 poolWethAfter = IERC20(WETH).balanceOf(address(ib));
        assertEq(poolWethAfter - poolWethBefore, repayAmount);
    }

    function testRepayFullEther() public {
        prepareBorrow();

        uint256 borrowAmount = 10e18;

        vm.prank(user1);
        wethExtension.borrowNativeToken(borrowAmount);

        uint256 poolWethBefore = IERC20(WETH).balanceOf(address(ib));
        uint256 repayAmount = 12e18;

        vm.prank(user1);
        vm.deal(user1, repayAmount);
        wethExtension.repayNativeToken{value: repayAmount}();

        uint256 poolWethAfter = IERC20(WETH).balanceOf(address(ib));
        assertEq(poolWethAfter - poolWethBefore, borrowAmount);
    }

    function prepareBorrow() internal {
        vm.prank(daiHolder);
        IERC20(DAI).safeTransfer(user1, 1000000e18);

        vm.startPrank(user1);
        IERC20(DAI).safeIncreaseAllowance(address(ib), 1000000e18);
        ib.supply(user1, DAI, 1000000e18);
        ib.enterMarket(user1, DAI);
        vm.stopPrank();
    }
}
