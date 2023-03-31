// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "v2-core/interfaces/IUniswapV2Callee.sol";
import "v2-core/interfaces/IUniswapV2Pair.sol";
import "v3-core/interfaces/callback/IUniswapV3SwapCallback.sol";
import "v3-core/interfaces/IUniswapV3Pool.sol";
import "v3-core/libraries/SafeCast.sol";
import "v3-core/libraries/TickMath.sol";
import "v3-periphery/libraries/Path.sol";
import "../interfaces/IronBankInterface.sol";
import "./interfaces/WethInterface.sol";
import "./libraries/UniswapV2Utils.sol";
import "./libraries/UniswapV3Utils.sol";

contract IronBankExtension is ReentrancyGuard, Ownable2Step, IUniswapV3SwapCallback, IUniswapV2Callee {
    using Path for bytes;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    /// @notice The action for supply native token
    bytes32 public constant SUPPLY_NATIVE_TOKEN = "SUPPLY_NATIVE_TOKEN";

    /// @notice The action for borrow native token
    bytes32 public constant BORROW_NATIVE_TOKEN = "BORROW_NATIVE_TOKEN";

    /// @notice The action for redeem native token
    bytes32 public constant REDEEM_NATIVE_TOKEN = "REDEEM_NATIVE_TOKEN";

    /// @notice The action for repay native token
    bytes32 public constant REPAY_NATIVE_TOKEN = "REPAY_NATIVE_TOKEN";

    /// @notice The action for add collateral
    bytes32 public constant ADD_COLLATERAL = "ADD_COLLATERAL";

    /// @notice The action for borrow asset
    bytes32 public constant BORROW_ASSET = "BORROW_ASSET";

    /// @notice The action for leverage long thru uniswap v3
    bytes32 public constant LEVERAGE_LONG_THRU_UNISWAP_V3 = "LEVERAGE_LONG_THRU_UNISWAP_V3";

    /// @notice The action for leverage long thru uniswap v2
    bytes32 public constant LEVERAGE_LONG_THRU_UNISWAP_V2 = "LEVERAGE_LONG_THRU_UNISWAP_V2";

    IronBankInterface public immutable ironBank;
    address public immutable uniV3Factory;
    address public immutable uniV2Factory;
    address public immutable weth;

    /**
     * @notice Construct a new IronBankExtension contract
     * @param ironBank_ The IronBank contract
     * @param uniV3Factory_ The Uniswap V3 factory contract
     * @param uniV2Factory_ The Uniswap V2 factory contract
     * @param weth_ The WETH contract
     */
    constructor(address ironBank_, address uniV3Factory_, address uniV2Factory_, address weth_) {
        ironBank = IronBankInterface(ironBank_);
        uniV3Factory = uniV3Factory_;
        uniV2Factory = uniV2Factory_;
        weth = weth_;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    struct Action {
        bytes32 name;
        bytes data;
    }

    /**
     * @notice Execute a list of actions in order
     * @param actions The list of actions
     */
    function execute(Action[] calldata actions) external payable {
        for (uint256 i = 0; i < actions.length;) {
            Action memory action = actions[i];
            if (action.name == SUPPLY_NATIVE_TOKEN) {
                supplyNativeToken();
            } else if (action.name == BORROW_NATIVE_TOKEN) {
                uint256 borrowAmount = abi.decode(action.data, (uint256));
                borrowNativeToken(borrowAmount);
            } else if (action.name == REDEEM_NATIVE_TOKEN) {
                uint256 redeemAmount = abi.decode(action.data, (uint256));
                redeemNativeToken(redeemAmount);
            } else if (action.name == REPAY_NATIVE_TOKEN) {
                repayNativeToken();
            } else if (action.name == ADD_COLLATERAL) {
                (address asset, uint256 amount) = abi.decode(action.data, (address, uint256));
                addCollateral(asset, amount);
            } else if (action.name == BORROW_ASSET) {
                (address asset, uint256 amount) = abi.decode(action.data, (address, uint256));
                borrowAsset(asset, amount);
            } else if (action.name == LEVERAGE_LONG_THRU_UNISWAP_V3) {
                (
                    address longAsset,
                    uint256 longAmount,
                    address shortAsset,
                    uint256 maxShortAmount,
                    address[] memory path,
                    uint24[] memory fee,
                    bool isOpenPosition
                ) = abi.decode(action.data, (address, uint256, address, uint256, address[], uint24[], bool));
                leverageUniV3(longAsset, longAmount, shortAsset, maxShortAmount, path, fee, isOpenPosition);
            } else if (action.name == LEVERAGE_LONG_THRU_UNISWAP_V2) {
                (
                    address longAsset,
                    uint256 longAmount,
                    address shortAsset,
                    uint256 maxShortAmount,
                    address[] memory path,
                    bool isOpenPosition
                ) = abi.decode(action.data, (address, uint256, address, uint256, address[], bool));
                leverageUniV2(longAsset, longAmount, shortAsset, maxShortAmount, path, isOpenPosition);
            } else {
                revert("invalid action");
            }

            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external {
        require(amount0Delta > 0 || amount1Delta > 0, "invalid amount");
        UniV3SwapData memory data = abi.decode(_data, (UniV3SwapData));
        (address tokenOut, address tokenIn, uint24 fee) = data.path.decodeFirstPool();
        IUniswapV3Pool pool = getUniV3Pool(tokenIn, tokenOut, fee);
        require(address(pool) == msg.sender, "invalid pool");

        if (tokenOut == data.longAsset) {
            IERC20(data.longAsset).safeIncreaseAllowance(address(ironBank), data.longAmount);
            if (data.isOpenPosition) {
                ironBank.enterMarket(data.caller, data.longAsset);
                ironBank.supply(data.caller, data.longAsset, data.longAmount);
            } else {
                ironBank.repay(data.caller, data.longAsset, data.longAmount);
            }
        }

        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);

        // Initiate the next swap or repay.
        if (data.path.hasMultiplePools()) {
            data.path = data.path.skipToken();

            // Make this pool as the recipient of the next swap.
            uniV3ExactOutputInternal(amountToPay, address(pool), data);
        } else {
            require(tokenIn == data.shortAsset, "mismatch short asset");
            require(amountToPay <= data.maxShortAmount, "short amount exceed max amount");

            if (data.isOpenPosition) {
                ironBank.borrow(data.caller, data.shortAsset, amountToPay);
            } else {
                ironBank.redeem(data.caller, data.shortAsset, amountToPay);
            }

            // Transfer the short asset to the pool.
            IERC20(tokenIn).safeTransfer(address(pool), amountToPay);
        }
    }

    /// @inheritdoc IUniswapV2Callee
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata _data) external {
        require(amount0 > 0 || amount1 > 0, "invalid amount");
        UniV2SwapData memory data = abi.decode(_data, (UniV2SwapData));
        (address tokenOut, address tokenIn) = (data.path[data.index], data.path[data.index + 1]);
        IUniswapV2Pair pool = getUniV2Pool(tokenIn, tokenOut);
        require(address(pool) == msg.sender, "invalid pool");
        require(sender == address(this), "invalid sender");

        if (tokenOut == data.longAsset) {
            IERC20(data.longAsset).safeIncreaseAllowance(address(ironBank), data.longAmount);
            if (data.isOpenPosition) {
                ironBank.enterMarket(data.caller, data.longAsset);
                ironBank.supply(data.caller, data.longAsset, data.longAmount);
            } else {
                ironBank.repay(data.caller, data.longAsset, data.longAmount);
            }
        }

        (uint256 reserve0, uint256 reserve1,) = pool.getReserves();
        (uint256 amountOut, uint256 reserveIn, uint256 reserveOut) =
            amount0 > 0 ? (amount0, reserve1, reserve0) : (amount1, reserve0, reserve1);
        uint256 amountToPay = UniswapV2Utils.getAmountIn(amountOut, reserveIn, reserveOut);

        // Initiate the next swap or repay.
        if (data.index < data.path.length - 2) {
            // Array slice is only supported for calldata arrays, so we use an index to track the current token.
            data.index++;
            uniV2ExactOutputInternal(amountToPay, data);
        } else {
            require(tokenIn == data.shortAsset, "mismatch short asset");
            require(amountToPay <= data.maxShortAmount, "short amount exceed max amount");

            if (data.isOpenPosition) {
                ironBank.borrow(data.caller, data.shortAsset, amountToPay);
            } else {
                ironBank.redeem(data.caller, data.shortAsset, amountToPay);
            }
        }

        // Since we can't make the recipient of the swap as the Uniswap v2 pool, we need to transfer the token to the pool.
        IERC20(tokenIn).safeTransfer(address(pool), amountToPay);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function seize(address recipient, address asset) external onlyOwner {
        IERC20(asset).safeTransfer(recipient, IERC20(asset).balanceOf(address(this)));
    }

    function seizeNative(address recipient) external onlyOwner {
        (bool sent,) = recipient.call{value: address(this).balance}("");
        require(sent, "failed to send native token");
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice Wraps the native token and supplies it to Iron Bank.
     */
    function supplyNativeToken() internal nonReentrant {
        WethInterface(weth).deposit{value: msg.value}();
        IERC20(weth).safeIncreaseAllowance(address(ironBank), msg.value);
        ironBank.supply(msg.sender, weth, msg.value);
    }

    /**
     * @notice Borrows the wrapped native token and unwraps it to the user.
     * @param borrowAmount The amount of the wrapped native token to borrow.
     */
    function borrowNativeToken(uint256 borrowAmount) internal nonReentrant {
        ironBank.borrow(msg.sender, weth, borrowAmount);
        WethInterface(weth).withdraw(borrowAmount);
        (bool sent,) = msg.sender.call{value: borrowAmount}("");
        require(sent, "failed to send native token");
    }

    /**
     * @notice Redeems the wrapped native token and unwraps it to the user.
     * @param redeemAmount The amount of the wrapped native token to redeem.
     */
    function redeemNativeToken(uint256 redeemAmount) internal nonReentrant {
        ironBank.redeem(msg.sender, weth, redeemAmount);
        WethInterface(weth).withdraw(redeemAmount);
        (bool sent,) = msg.sender.call{value: redeemAmount}("");
        require(sent, "failed to send native token");
    }

    /**
     * @notice Wraps the native token and repays it to Iron Bank.
     * @dev If the amount of the native token is greater than the borrow balance, the excess amount will be sent back to the user.
     */
    function repayNativeToken() internal nonReentrant {
        uint256 repayAmount = msg.value;

        ironBank.accrueInterest(weth);
        uint256 borrowBalance = ironBank.getBorrowBalance(msg.sender, weth);
        if (repayAmount > borrowBalance) {
            WethInterface(weth).deposit{value: borrowBalance}();
            IERC20(weth).safeIncreaseAllowance(address(ironBank), borrowBalance);
            ironBank.repay(msg.sender, weth, borrowBalance);
            (bool sent,) = msg.sender.call{value: repayAmount - borrowBalance}("");
            require(sent, "failed to send native token");
        } else {
            WethInterface(weth).deposit{value: repayAmount}();
            IERC20(weth).safeIncreaseAllowance(address(ironBank), repayAmount);
            ironBank.repay(msg.sender, weth, repayAmount);
        }
    }

    /**
     * @notice Supplies the collateral to Iron Bank.
     * @param asset The address of the collateral asset.
     * @param amount The amount of the collateral asset to supply.
     */
    function addCollateral(address asset, uint256 amount) internal nonReentrant {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(asset).safeIncreaseAllowance(address(ironBank), amount);
        ironBank.supply(msg.sender, asset, amount);
        ironBank.enterMarket(msg.sender, asset);
    }

    /**
     * @notice Borrows the asset from Iron Bank.
     * @param asset The address of the asset to borrow.
     * @param amount The amount of the asset to borrow.
     */
    function borrowAsset(address asset, uint256 amount) internal nonReentrant {
        ironBank.borrow(msg.sender, asset, amount);
        IERC20(asset).safeTransfer(msg.sender, amount);
    }

    struct UniV3SwapData {
        address caller;
        address longAsset;
        uint256 longAmount;
        address shortAsset;
        uint256 maxShortAmount;
        bytes path;
        bool isOpenPosition;
    }

    /**
     * @notice Leverage long on Iron Bank through Uniswap v3.
     * @param longAsset The address of the long asset.
     * @param longAmount The amount of the long asset to supply.
     * @param shortAsset The address of the short asset.
     * @param maxShortAmount The maximum amount of the short asset to borrow.
     * @param path The path of the Uniswap v3 swap.
     * @param fee The fee of the Uniswap v3 swap.
     * @param isOpenPosition Whether to open a new position or close an existing position.
     */
    function leverageUniV3(
        address longAsset,
        uint256 longAmount,
        address shortAsset,
        uint256 maxShortAmount,
        address[] memory path,
        uint24[] memory fee,
        bool isOpenPosition
    ) internal nonReentrant {
        require(longAsset != shortAsset, "invalid long or short asset");
        if (longAmount == type(uint256).max) {
            require(!isOpenPosition);
            ironBank.accrueInterest(longAsset);
            longAmount = ironBank.getBorrowBalance(msg.sender, longAsset);
        }
        require(longAmount > 0, "invalid long amount");
        require(path.length >= 2 && path[0] == longAsset && path[path.length - 1] == shortAsset, "invalid path");
        require(fee.length == path.length - 1, "invalid fee");

        bytes memory uniV3Path;
        for (uint256 i = 0; i < path.length; i++) {
            uniV3Path = abi.encodePacked(uniV3Path, path[i]);
            if (i != path.length - 1) {
                uniV3Path = abi.encodePacked(uniV3Path, fee[i]);
            }
        }

        uniV3ExactOutputInternal(
            longAmount,
            address(this),
            UniV3SwapData({
                caller: msg.sender,
                longAsset: longAsset,
                longAmount: longAmount,
                shortAsset: shortAsset,
                maxShortAmount: maxShortAmount,
                path: uniV3Path,
                isOpenPosition: isOpenPosition
            })
        );
    }

    struct UniV2SwapData {
        address caller;
        address longAsset;
        uint256 longAmount;
        address shortAsset;
        uint256 maxShortAmount;
        address[] path;
        uint256 index;
        bool isOpenPosition;
    }

    /**
     * @notice Leverage long on Iron Bank through Uniswap v2.
     * @param longAsset The address of the long asset.
     * @param longAmount The amount of the long asset to supply.
     * @param shortAsset The address of the short asset.
     * @param maxShortAmount The maximum amount of the short asset to borrow.
     * @param path The path of the Uniswap v2 swap.
     * @param isOpenPosition Whether to open a new position or close an existing position.
     */
    function leverageUniV2(
        address longAsset,
        uint256 longAmount,
        address shortAsset,
        uint256 maxShortAmount,
        address[] memory path,
        bool isOpenPosition
    ) internal nonReentrant {
        require(longAsset != shortAsset, "invalid long or short asset");
        if (longAmount == type(uint256).max) {
            require(!isOpenPosition);
            ironBank.accrueInterest(longAsset);
            longAmount = ironBank.getBorrowBalance(msg.sender, longAsset);
        }
        require(longAmount > 0, "invalid long amount");
        require(path.length >= 2 && path[0] == longAsset && path[path.length - 1] == shortAsset, "invalid path");

        uniV2ExactOutputInternal(
            longAmount,
            UniV2SwapData({
                caller: msg.sender,
                longAsset: longAsset,
                longAmount: longAmount,
                shortAsset: shortAsset,
                maxShortAmount: maxShortAmount,
                path: path,
                index: 0,
                isOpenPosition: isOpenPosition
            })
        );
    }

    /**
     * @notice Exact output swap on Uniswap v3.
     * @param amountOut The amount of the output asset.
     * @param recipient The address to receive the asset.
     * @param data The swap data.
     */
    function uniV3ExactOutputInternal(uint256 amountOut, address recipient, UniV3SwapData memory data) private {
        (address tokenOut, address tokenIn, uint24 fee) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        getUniV3Pool(tokenIn, tokenOut, fee).swap(
            recipient,
            zeroForOne,
            -amountOut.toInt256(),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(data)
        );
    }

    /**
     * @notice Exact output swap on Uniswap v2.
     * @param amountOut The amount of the output asset.
     * @param data The swap data.
     */
    function uniV2ExactOutputInternal(uint256 amountOut, UniV2SwapData memory data) private {
        (address tokenA, address tokenB) = (data.path[data.index], data.path[data.index + 1]);

        (uint256 amount0, uint256 amount1) = tokenA < tokenB ? (amountOut, uint256(0)) : (uint256(0), amountOut);

        getUniV2Pool(tokenA, tokenB).swap(amount0, amount1, address(this), abi.encode(data));
    }

    /**
     * @notice Returns the Uniswap v3 pool.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @param fee The fee of the pool.
     */
    function getUniV3Pool(address tokenA, address tokenB, uint24 fee) private view returns (IUniswapV3Pool pool) {
        UniswapV3Utils.PoolKey memory poolKey = UniswapV3Utils.getPoolKey(tokenA, tokenB, fee);
        pool = IUniswapV3Pool(UniswapV3Utils.computeAddress(uniV3Factory, poolKey));
    }

    /**
     * @notice Returns the Uniswap v2 pool.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     */
    function getUniV2Pool(address tokenA, address tokenB) private view returns (IUniswapV2Pair pair) {
        pair = IUniswapV2Pair(UniswapV2Utils.computeAddress(uniV2Factory, tokenA, tokenB));
    }

    receive() external payable {}
}
