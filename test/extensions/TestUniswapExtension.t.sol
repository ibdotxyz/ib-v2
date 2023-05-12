// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/Test.sol";
import "../Common.t.sol";

contract UniswapExtensionTest is Test, Common {
    uint16 internal constant reserveFactor = 1000; // 10%

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address constant uniswapV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant uniswapV2Factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;
    UniswapExtension extension;

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

        extension = createUniswapExtension(admin, ib, uniswapV3Factory, uniswapV2Factory, WETH, STETH, WSTETH);
    }

    function testCannotExecuteForInvalidAction() public {
        vm.prank(user1);
        UniswapExtension.Action[] memory actions = new UniswapExtension.Action[](1);
        actions[0] = UniswapExtension.Action({name: "INVALID_ACTION", data: bytes("")});
        vm.expectRevert("invalid action");
        extension.execute(actions);
    }

    function testCannotExecuteForTrnasactionTooOld() public {
        uint256 deadline = block.timestamp - 1;

        bytes memory revertMsg = "transaction too old";

        checkUniV3SwapExactOut(
            address(market1),
            0,
            address(market1),
            0,
            new address[](0),
            new uint24[](0),
            bytes32(""),
            deadline,
            revertMsg
        );
        checkUniV3SwapExactIn(
            address(market1),
            0,
            address(market1),
            0,
            new address[](0),
            new uint24[](0),
            bytes32(""),
            deadline,
            revertMsg
        );
        checkUniV2SwapExactOut(
            address(market1), 0, address(market1), 0, new address[](0), bytes32(""), deadline, revertMsg
        );
        checkUniV2SwapExactIn(
            address(market1), 0, address(market1), 0, new address[](0), bytes32(""), deadline, revertMsg
        );
    }

    function testCannotExecuteForInvalidSwapAssetPair() public {
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory revertMsg = "invalid swap asset pair";

        checkUniV3SwapExactOut(
            address(market1),
            0,
            address(market1),
            0,
            new address[](0),
            new uint24[](0),
            bytes32(""),
            deadline,
            revertMsg
        );
        checkUniV3SwapExactIn(
            address(market1),
            0,
            address(market1),
            0,
            new address[](0),
            new uint24[](0),
            bytes32(""),
            deadline,
            revertMsg
        );
        checkUniV2SwapExactOut(
            address(market1), 0, address(market1), 0, new address[](0), bytes32(""), deadline, revertMsg
        );
        checkUniV2SwapExactIn(
            address(market1), 0, address(market1), 0, new address[](0), bytes32(""), deadline, revertMsg
        );
    }

    function testCannotExecuteForUnsupportedSubAction() public {
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory revertMsg = "unsupported sub-action";

        checkUniV3SwapExactOut(
            address(market1),
            type(uint256).max,
            address(market2),
            0,
            new address[](0),
            new uint24[](0),
            bytes32("SUB_ACTION_OPEN_LONG_POSITION"),
            deadline,
            revertMsg
        );
        checkUniV3SwapExactIn(
            address(market1),
            type(uint256).max,
            address(market2),
            0,
            new address[](0),
            new uint24[](0),
            bytes32("SUB_ACTION_OPEN_LONG_POSITION"),
            deadline,
            revertMsg
        );
        checkUniV2SwapExactOut(
            address(market1),
            type(uint256).max,
            address(market2),
            0,
            new address[](0),
            bytes32("SUB_ACTION_OPEN_LONG_POSITION"),
            deadline,
            revertMsg
        );
        checkUniV2SwapExactIn(
            address(market1),
            type(uint256).max,
            address(market2),
            0,
            new address[](0),
            bytes32("SUB_ACTION_OPEN_LONG_POSITION"),
            deadline,
            revertMsg
        );
    }

    function testCannotExecuteForInvalidSwapAmount() public {
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory revertMsg1 = "invalid swap out amount";
        bytes memory revertMsg2 = "invalid swap in amount";

        checkUniV3SwapExactOut(
            address(market1),
            0,
            address(market2),
            0,
            new address[](0),
            new uint24[](0),
            bytes32(""),
            deadline,
            revertMsg1
        );
        checkUniV3SwapExactIn(
            address(market1),
            0,
            address(market2),
            0,
            new address[](0),
            new uint24[](0),
            bytes32(""),
            deadline,
            revertMsg2
        );
        checkUniV2SwapExactOut(
            address(market1), 0, address(market2), 0, new address[](0), bytes32(""), deadline, revertMsg1
        );
        checkUniV2SwapExactIn(
            address(market1), 0, address(market2), 0, new address[](0), bytes32(""), deadline, revertMsg2
        );
    }

    function testCannotExecuteForInvalidPath() public {
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory revertMsg = "invalid path";

        // invalid path length
        address[] memory path = new address[](1);

        checkUniV3SwapExactOut(
            address(market1), 100e18, address(market2), 0, path, new uint24[](0), bytes32(""), deadline, revertMsg
        );
        checkUniV3SwapExactIn(
            address(market1), 100e18, address(market2), 0, path, new uint24[](0), bytes32(""), deadline, revertMsg
        );
        checkUniV2SwapExactOut(address(market1), 100e18, address(market2), 0, path, bytes32(""), deadline, revertMsg);
        checkUniV2SwapExactIn(address(market1), 100e18, address(market2), 0, path, bytes32(""), deadline, revertMsg);

        // invalid path content
        path = new address[](2);
        path[0] = address(market1);
        path[1] = address(market1);

        checkUniV3SwapExactOut(
            address(market1), 100e18, address(market2), 0, path, new uint24[](0), bytes32(""), deadline, revertMsg
        );
        checkUniV3SwapExactIn(
            address(market1), 100e18, address(market2), 0, path, new uint24[](0), bytes32(""), deadline, revertMsg
        );
        checkUniV2SwapExactOut(address(market1), 100e18, address(market2), 0, path, bytes32(""), deadline, revertMsg);
        checkUniV2SwapExactIn(address(market1), 100e18, address(market2), 0, path, bytes32(""), deadline, revertMsg);

        // invalid path content
        path = new address[](2);
        path[0] = address(market2);
        path[1] = address(market2);

        checkUniV3SwapExactOut(
            address(market1), 100e18, address(market2), 0, path, new uint24[](0), bytes32(""), deadline, revertMsg
        );
        checkUniV3SwapExactIn(
            address(market1), 100e18, address(market2), 0, path, new uint24[](0), bytes32(""), deadline, revertMsg
        );
        checkUniV2SwapExactOut(address(market1), 100e18, address(market2), 0, path, bytes32(""), deadline, revertMsg);
        checkUniV2SwapExactIn(address(market1), 100e18, address(market2), 0, path, bytes32(""), deadline, revertMsg);
    }

    function testCannotExecuteForInvalidFee() public {
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory revertMsg = "invalid fee";

        address[] memory path = new address[](2);
        path[0] = address(market1);
        path[1] = address(market2);

        uint24[] memory fees = new uint24[](2);

        checkUniV3SwapExactOut(
            address(market1), 100e18, address(market2), 0, path, fees, bytes32(""), deadline, revertMsg
        );
        checkUniV3SwapExactIn(
            address(market1), 100e18, address(market2), 0, path, fees, bytes32(""), deadline, revertMsg
        );
    }

    function testSeize() public {
        deal(address(market1), address(extension), 100e18);

        vm.prank(admin);
        extension.seize(user1, address(market1));

        assertEq(IERC20(market1).balanceOf(user1), 100e18);
    }

    function testCannotSeizeForNotowner() public {
        deal(address(market1), address(extension), 100e18);

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        extension.seize(user1, address(market1));
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

    function checkUniV3SwapExactOut(
        address swapOutAsset,
        uint256 swapOutAmount,
        address swapInAsset,
        uint256 maxSwapInAmount,
        address[] memory path,
        uint24[] memory fee,
        bytes32 subAction,
        uint256 deadline,
        bytes memory revertMsg
    ) internal {
        vm.prank(user1);
        UniswapExtension.Action[] memory actions = new UniswapExtension.Action[](1);
        actions[0] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V3_EXACT_OUTPUT",
            data: abi.encode(swapOutAsset, swapOutAmount, swapInAsset, maxSwapInAmount, path, fee, subAction, deadline)
        });
        vm.expectRevert(revertMsg);
        extension.execute(actions);
    }

    function checkUniV3SwapExactIn(
        address swapInAsset,
        uint256 swapInAmount,
        address swapOutAsset,
        uint256 minSwapOutAmount,
        address[] memory path,
        uint24[] memory fee,
        bytes32 subAction,
        uint256 deadline,
        bytes memory revertMsg
    ) internal {
        vm.prank(user1);
        UniswapExtension.Action[] memory actions = new UniswapExtension.Action[](1);
        actions[0] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V3_EXACT_INPUT",
            data: abi.encode(swapInAsset, swapInAmount, swapOutAsset, minSwapOutAmount, path, fee, subAction, deadline)
        });
        vm.expectRevert(revertMsg);
        extension.execute(actions);
    }

    function checkUniV2SwapExactOut(
        address swapOutAsset,
        uint256 swapOutAmount,
        address swapInAsset,
        uint256 maxSwapInAmount,
        address[] memory path,
        bytes32 subAction,
        uint256 deadline,
        bytes memory revertMsg
    ) internal {
        vm.prank(user1);
        UniswapExtension.Action[] memory actions = new UniswapExtension.Action[](1);
        actions[0] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V2_EXACT_OUTPUT",
            data: abi.encode(swapOutAsset, swapOutAmount, swapInAsset, maxSwapInAmount, path, subAction, deadline)
        });
        vm.expectRevert(revertMsg);
        extension.execute(actions);
    }

    function checkUniV2SwapExactIn(
        address swapInAsset,
        uint256 swapInAmount,
        address swapOutAsset,
        uint256 minSwapOutAmount,
        address[] memory path,
        bytes32 subAction,
        uint256 deadline,
        bytes memory revertMsg
    ) internal {
        vm.prank(user1);
        UniswapExtension.Action[] memory actions = new UniswapExtension.Action[](1);
        actions[0] = UniswapExtension.Action({
            name: "ACTION_UNISWAP_V2_EXACT_INPUT",
            data: abi.encode(swapInAsset, swapInAmount, swapOutAsset, minSwapOutAmount, path, subAction, deadline)
        });
        vm.expectRevert(revertMsg);
        extension.execute(actions);
    }
}
