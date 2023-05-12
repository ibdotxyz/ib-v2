// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "../Common.t.sol";

contract TxBuilderExtensionTest is Test, Common {
    uint16 internal constant reserveFactor = 1000; // 10%

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    TxBuilderExtension extension;

    ERC20Market market;

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

        (market,,) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);

        extension = createTxBuilderExtension(admin, ib, WETH, STETH, WSTETH);
    }

    function testCannotExecuteForInvalidAction() public {
        vm.prank(user1);
        TxBuilderExtension.Action[] memory actions = new TxBuilderExtension.Action[](1);
        actions[0] = TxBuilderExtension.Action({name: "INVALID_ACTION", data: bytes("")});
        vm.expectRevert("invalid action");
        extension.execute(actions);
    }

    function testCannotOnDeferredLiquidityCheck() public {
        vm.prank(user1);
        vm.expectRevert("untrusted message sender");
        extension.onDeferredLiquidityCheck(bytes(""));
    }

    function testSeize() public {
        deal(address(market), address(extension), 100e18);

        vm.prank(admin);
        extension.seize(user1, address(market));

        assertEq(IERC20(market).balanceOf(user1), 100e18);
    }

    function testCannotSeizeForNotowner() public {
        deal(address(market), address(extension), 100e18);

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        extension.seize(user1, address(market));
    }

    function testSeizeNative() public {
        vm.deal(address(extension), 100e18);

        vm.prank(admin);
        extension.seizeNative(user1);

        assertEq(user1.balance, 100e18);
    }

    function testSeizeNativeForNotOwner() public {
        vm.deal(address(extension), 100e18);

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        extension.seizeNative(user1);
    }
}
