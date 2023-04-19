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

    /**
     * User actions
     */

    /// @notice The action for supplying native token
    bytes32 public constant ACTION_SUPPLY_NATIVE_TOKEN = "ACTION_SUPPLY_NATIVE_TOKEN";

    /// @notice The action for borrowing native token
    bytes32 public constant ACTION_BORROW_NATIVE_TOKEN = "ACTION_BORROW_NATIVE_TOKEN";

    /// @notice The action for redeeming native token
    bytes32 public constant ACTION_REDEEM_NATIVE_TOKEN = "ACTION_REDEEM_NATIVE_TOKEN";

    /// @notice The action for repaying native token
    bytes32 public constant ACTION_REPAY_NATIVE_TOKEN = "ACTION_REPAY_NATIVE_TOKEN";

    /// @notice The action for supplying asset
    bytes32 public constant ACTION_SUPPLY = "ACTION_SUPPLY";

    /// @notice The action for borrowing asset
    bytes32 public constant ACTION_BORROW = "ACTION_BORROW";

    /// @notice The action for redeeming asset
    bytes32 public constant ACTION_REDEEM = "ACTION_REDEEM";

    /// @notice The action for repaying asset
    bytes32 public constant ACTION_REPAY = "ACTION_REPAY";

    /// @notice The action for exact output swap thru Uniswap v3
    bytes32 public constant ACTION_UNISWAP_V3_EXACT_OUTPUT = "ACTION_UNISWAP_V3_EXACT_OUTPUT";

    /// @notice The action for exact input swap thru Uniswap v3
    bytes32 public constant ACTION_UNISWAP_V3_EXACT_INPUT = "ACTION_UNISWAP_V3_EXACT_INPUT";

    /// @notice The action for exact output swap thru Uniswap v2
    bytes32 public constant ACTION_UNISWAP_V2_EXACT_OUTPUT = "ACTION_UNISWAP_V2_EXACT_OUTPUT";

    /// @notice The action for exact input swap thru Uniswap v2
    bytes32 public constant ACTION_UNISWAP_V2_EXACT_INPUT = "ACTION_UNISWAP_V2_EXACT_INPUT";

    /// @notice The sub-action for opening long position
    bytes32 public constant SUB_ACTION_OPEN_LONG_POSITION = "SUB_ACTION_OPEN_LONG_POSITION";

    /// @notice The sub-action for closing long position
    bytes32 public constant SUB_ACTION_CLOSE_LONG_POSITION = "SUB_ACTION_CLOSE_LONG_POSITION";

    /// @notice The sub-action for opening short position
    bytes32 public constant SUB_ACTION_OPEN_SHORT_POSITION = "SUB_ACTION_OPEN_SHORT_POSITION";

    /// @notice The sub-action for closing short position
    bytes32 public constant SUB_ACTION_CLOSE_SHORT_POSITION = "SUB_ACTION_CLOSE_SHORT_POSITION";

    /// @notice The sub-action for swapping debt
    bytes32 public constant SUB_ACTION_SWAP_DEBT = "SUB_ACTION_SWAP_DEBT";

    /// @notice The sub-action for swapping collateral
    bytes32 public constant SUB_ACTION_SWAP_COLLATERAL = "SUB_ACTION_SWAP_COLLATERAL";

    /// @dev Used as the placeholder value for uniV3AmountInCached, uniV3AmountOutCached, uniV2AmountInCached and
    /// uniV2AmountOutCached, because the computed amount in/out for an exact output/input swap can never actually be
    /// this value.
    uint256 private constant DEFAULT_AMOUNT_CACHED = type(uint256).max;

    /// @dev Transient storage variable used for returning the computed amount in for an exact output Uniswap v3 swap.
    uint256 private uniV3AmountInCached = DEFAULT_AMOUNT_CACHED;

    /// @dev Transient storage variable used for returning the computed amount in for an exact input Uniswap v3 swap.
    uint256 private uniV3AmountOutCached = DEFAULT_AMOUNT_CACHED;

    /// @dev Transient storage variable used for returning the computed amount in for an exact output Uniswap v2 swap.
    uint256 private uniV2AmountInCached = DEFAULT_AMOUNT_CACHED;

    /// @dev Transient storage variable used for returning the computed amount in for an exact input Uniswap v2 swap.
    uint256 private uniV2AmountOutCached = DEFAULT_AMOUNT_CACHED;

    IronBankInterface public immutable ironBank;
    address public immutable uniV3Factory;
    address public immutable uniV2Factory;
    address public immutable weth;

    /**
     * @notice Modifier to check if the deadline has passed
     * @param deadline The deadline to check
     */
    modifier checkDeadline(uint256 deadline) {
        require(block.timestamp <= deadline, "Transaction too old");
        _;
    }

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
            if (action.name == ACTION_SUPPLY_NATIVE_TOKEN) {
                supplyNativeToken();
            } else if (action.name == ACTION_BORROW_NATIVE_TOKEN) {
                uint256 borrowAmount = abi.decode(action.data, (uint256));
                borrowNativeToken(borrowAmount);
            } else if (action.name == ACTION_REDEEM_NATIVE_TOKEN) {
                uint256 redeemAmount = abi.decode(action.data, (uint256));
                redeemNativeToken(redeemAmount);
            } else if (action.name == ACTION_REPAY_NATIVE_TOKEN) {
                repayNativeToken();
            } else if (action.name == ACTION_SUPPLY) {
                (address asset, uint256 amount) = abi.decode(action.data, (address, uint256));
                supply(asset, amount);
            } else if (action.name == ACTION_BORROW) {
                (address asset, uint256 amount) = abi.decode(action.data, (address, uint256));
                borrow(asset, amount);
            } else if (action.name == ACTION_REDEEM) {
                (address asset, uint256 amount) = abi.decode(action.data, (address, uint256));
                redeem(asset, amount);
            } else if (action.name == ACTION_REPAY) {
                (address asset, uint256 amount) = abi.decode(action.data, (address, uint256));
                repay(asset, amount);
            } else if (action.name == ACTION_UNISWAP_V3_EXACT_OUTPUT) {
                (
                    address swapOutAsset,
                    uint256 swapOutAmount,
                    address swapInAsset,
                    uint256 maxSwapInAmount,
                    address[] memory path,
                    uint24[] memory fee,
                    bytes32 subAction,
                    uint256 deadline
                ) = abi.decode(action.data, (address, uint256, address, uint256, address[], uint24[], bytes32, uint256));
                uniV3SwapExactOut(
                    swapOutAsset, swapOutAmount, swapInAsset, maxSwapInAmount, path, fee, subAction, deadline
                );
            } else if (action.name == ACTION_UNISWAP_V3_EXACT_INPUT) {
                (
                    address swapInAsset,
                    uint256 swapInAmount,
                    address swapOutAsset,
                    uint256 minSwapOutAmount,
                    address[] memory path,
                    uint24[] memory fee,
                    bytes32 subAction,
                    uint256 deadline
                ) = abi.decode(action.data, (address, uint256, address, uint256, address[], uint24[], bytes32, uint256));
                uniV3SwapExactIn(
                    swapInAsset, swapInAmount, swapOutAsset, minSwapOutAmount, path, fee, subAction, deadline
                );
            } else if (action.name == ACTION_UNISWAP_V2_EXACT_OUTPUT) {
                (
                    address swapOutAsset,
                    uint256 swapOutAmount,
                    address swapInAsset,
                    uint256 maxSwapInAmount,
                    address[] memory path,
                    bytes32 subAction,
                    uint256 deadline
                ) = abi.decode(action.data, (address, uint256, address, uint256, address[], bytes32, uint256));
                uniV2SwapExactOut(swapOutAsset, swapOutAmount, swapInAsset, maxSwapInAmount, path, subAction, deadline);
            } else if (action.name == ACTION_UNISWAP_V2_EXACT_INPUT) {
                (
                    address swapOutAsset,
                    uint256 swapOutAmount,
                    address swapInAsset,
                    uint256 maxSwapInAmount,
                    address[] memory path,
                    bytes32 subAction,
                    uint256 deadline
                ) = abi.decode(action.data, (address, uint256, address, uint256, address[], bytes32, uint256));
                uniV2SwapExactIn(swapOutAsset, swapOutAmount, swapInAsset, maxSwapInAmount, path, subAction, deadline);
            } else {
                revert("invalid action");
            }

            unchecked {
                i++;
            }
        }
    }

    struct UniV3SwapData {
        address caller;
        address swapOutAsset;
        address swapInAsset;
        bytes path;
        bytes32 subAction;
    }

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external {
        require(amount0Delta > 0 || amount1Delta > 0, "invalid amount");
        UniV3SwapData memory data = abi.decode(_data, (UniV3SwapData));
        (address tokenIn, address tokenOut, uint24 fee) = data.path.decodeFirstPool();
        IUniswapV3Pool pool = getUniV3Pool(tokenIn, tokenOut, fee);
        require(address(pool) == msg.sender, "invalid pool");

        (bool isExactInput, uint256 amountToPay, uint256 amountReceived) = amount0Delta > 0
            ? (tokenIn < tokenOut, uint256(amount0Delta), uint256(-amount1Delta))
            : (tokenOut < tokenIn, uint256(amount1Delta), uint256(-amount0Delta));

        if (isExactInput) {
            // Initiate the next swap or pay.
            if (data.path.hasMultiplePools()) {
                data.path = data.path.skipToken();

                uniV3ExactInputInternal(amountReceived, address(this), data);
            } else {
                require(tokenOut == data.swapOutAsset, "mismatch swap out asset");

                uniV3AmountOutCached = amountReceived;

                IERC20(data.swapOutAsset).safeIncreaseAllowance(address(ironBank), amountReceived);
                if (data.subAction == SUB_ACTION_OPEN_SHORT_POSITION || data.subAction == SUB_ACTION_SWAP_COLLATERAL) {
                    ironBank.supply(address(this), data.caller, data.swapOutAsset, amountReceived);
                } else if (data.subAction == SUB_ACTION_CLOSE_LONG_POSITION) {
                    ironBank.repay(address(this), data.caller, data.swapOutAsset, amountReceived);
                } else {
                    revert("invalid sub-action");
                }
            }

            if (tokenIn == data.swapInAsset) {
                if (data.subAction == SUB_ACTION_OPEN_SHORT_POSITION) {
                    ironBank.borrow(data.caller, address(this), data.swapInAsset, amountToPay);
                } else if (
                    data.subAction == SUB_ACTION_CLOSE_LONG_POSITION || data.subAction == SUB_ACTION_SWAP_COLLATERAL
                ) {
                    ironBank.redeem(data.caller, address(this), data.swapInAsset, amountToPay);
                } else {
                    revert("invalid sub-action");
                }
            }

            // Although we already know the amount to pay, we can't pay it at the beginning, because we can't redeem or
            // borrow for users until we supply or repay for users in the last step of the swap.
            IERC20(tokenIn).safeTransfer(address(pool), amountToPay);
        } else {
            if (tokenIn == data.swapOutAsset) {
                IERC20(data.swapOutAsset).safeIncreaseAllowance(address(ironBank), amountReceived);
                if (data.subAction == SUB_ACTION_OPEN_LONG_POSITION) {
                    ironBank.supply(address(this), data.caller, data.swapOutAsset, amountReceived);
                } else if (data.subAction == SUB_ACTION_CLOSE_SHORT_POSITION || data.subAction == SUB_ACTION_SWAP_DEBT)
                {
                    ironBank.repay(address(this), data.caller, data.swapOutAsset, amountReceived);
                } else {
                    revert("invalid sub-action");
                }
            }

            // Initiate the next swap or pay.
            if (data.path.hasMultiplePools()) {
                data.path = data.path.skipToken();

                // Make this pool as the recipient of the next swap.
                uniV3ExactOutputInternal(amountToPay, address(pool), data);
            } else {
                require(tokenOut == data.swapInAsset, "mismatch swap in asset");

                uniV3AmountInCached = amountToPay;

                if (data.subAction == SUB_ACTION_OPEN_LONG_POSITION || data.subAction == SUB_ACTION_SWAP_DEBT) {
                    ironBank.borrow(data.caller, address(this), data.swapInAsset, amountToPay);
                } else if (data.subAction == SUB_ACTION_CLOSE_SHORT_POSITION) {
                    ironBank.redeem(data.caller, address(this), data.swapInAsset, amountToPay);
                } else {
                    revert("invalid sub-action");
                }

                // Transfer the asset to the pool.
                IERC20(tokenOut).safeTransfer(address(pool), amountToPay);
            }
        }
    }

    struct UniV2SwapData {
        address caller;
        address swapOutAsset;
        address swapInAsset;
        uint256[] amounts;
        address[] path;
        uint256 index;
        bytes32 subAction;
    }

    /// @inheritdoc IUniswapV2Callee
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata _data) external {
        require(amount0 > 0 || amount1 > 0, "invalid amount");
        UniV2SwapData memory data = abi.decode(_data, (UniV2SwapData));
        (address tokenIn, address tokenOut) = (data.path[data.index], data.path[data.index + 1]);
        IUniswapV2Pair pool = getUniV2Pool(tokenIn, tokenOut);
        require(address(pool) == msg.sender, "invalid pool");
        require(sender == address(this), "invalid sender");

        /**
         *             amounts[0]  amounts[1]  amounts[2]   ...
         * exactInput:  pay      -> receive
         *                          pay      -> receive
         *                                      pay      -> ...
         * exactOutput: receive  <- pay
         *                          receive  <- pay
         *                                      receive  <- ...
         */
        (bool isExactInput, uint256 amountReceived) =
            amount0 > 0 ? (tokenIn > tokenOut, amount0) : (tokenIn < tokenOut, amount1);
        uint256 amountToPay = isExactInput ? data.amounts[data.index] : data.amounts[data.index + 1];

        if (isExactInput) {
            // Initiate the next swap or pay.
            if (data.index < data.path.length - 2) {
                // Array slice is only supported for calldata arrays, so we use an index to track the current token.
                data.index++;
                uniV2ExactInputInternal(data);
            } else {
                require(tokenOut == data.swapOutAsset, "mismatch swap out asset");

                uniV2AmountOutCached = amountReceived;

                IERC20(data.swapOutAsset).safeIncreaseAllowance(address(ironBank), amountReceived);
                if (data.subAction == SUB_ACTION_OPEN_SHORT_POSITION || data.subAction == SUB_ACTION_SWAP_COLLATERAL) {
                    ironBank.supply(address(this), data.caller, data.swapOutAsset, amountReceived);
                } else if (data.subAction == SUB_ACTION_CLOSE_LONG_POSITION) {
                    ironBank.repay(address(this), data.caller, data.swapOutAsset, amountReceived);
                } else {
                    revert("invalid sub-action");
                }
            }

            if (tokenIn == data.swapInAsset) {
                if (data.subAction == SUB_ACTION_OPEN_SHORT_POSITION) {
                    ironBank.borrow(data.caller, address(this), data.swapInAsset, amountToPay);
                } else if (
                    data.subAction == SUB_ACTION_CLOSE_LONG_POSITION || data.subAction == SUB_ACTION_SWAP_COLLATERAL
                ) {
                    ironBank.redeem(data.caller, address(this), data.swapInAsset, amountToPay);
                } else {
                    revert("invalid sub-action");
                }
            }

            // Transfer the token to the pool and conclude the swap.
            IERC20(tokenIn).safeTransfer(address(pool), amountToPay);
        } else {
            if (tokenIn == data.swapOutAsset) {
                IERC20(data.swapOutAsset).safeIncreaseAllowance(address(ironBank), amountReceived);
                if (data.subAction == SUB_ACTION_OPEN_LONG_POSITION) {
                    ironBank.supply(address(this), data.caller, data.swapOutAsset, amountReceived);
                } else if (data.subAction == SUB_ACTION_CLOSE_SHORT_POSITION || data.subAction == SUB_ACTION_SWAP_DEBT)
                {
                    ironBank.repay(address(this), data.caller, data.swapOutAsset, amountReceived);
                } else {
                    revert("invalid sub-action");
                }
            }

            // Initiate the next swap or pay.
            if (data.index < data.path.length - 2) {
                // Array slice is only supported for calldata arrays, so we use an index to track the current token.
                data.index++;
                uniV2ExactOutputInternal(data);
            } else {
                require(tokenOut == data.swapInAsset, "mismatch swap in asset");

                uniV2AmountInCached = amountToPay;

                if (data.subAction == SUB_ACTION_OPEN_LONG_POSITION || data.subAction == SUB_ACTION_SWAP_DEBT) {
                    ironBank.borrow(data.caller, address(this), data.swapInAsset, amountToPay);
                } else if (data.subAction == SUB_ACTION_CLOSE_SHORT_POSITION) {
                    ironBank.redeem(data.caller, address(this), data.swapInAsset, amountToPay);
                } else {
                    revert("invalid sub-action");
                }
            }

            // Transfer the token to the pool and conclude the swap.
            IERC20(tokenOut).safeTransfer(address(pool), amountToPay);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice Admin seizes the asset from the contract.
     * @param recipient The recipient of the seized asset.
     * @param asset The asset to seize.
     */
    function seize(address recipient, address asset) external onlyOwner {
        IERC20(asset).safeTransfer(recipient, IERC20(asset).balanceOf(address(this)));
    }

    /**
     * @notice Admin seizes the native token from the contract.
     * @param recipient The recipient of the seized native token.
     */
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
        ironBank.supply(address(this), msg.sender, weth, msg.value);
    }

    /**
     * @notice Borrows the wrapped native token and unwraps it to the user.
     * @param borrowAmount The amount of the wrapped native token to borrow.
     */
    function borrowNativeToken(uint256 borrowAmount) internal nonReentrant {
        ironBank.borrow(msg.sender, address(this), weth, borrowAmount);
        WethInterface(weth).withdraw(borrowAmount);
        (bool sent,) = msg.sender.call{value: borrowAmount}("");
        require(sent, "failed to send native token");
    }

    /**
     * @notice Redeems the wrapped native token and unwraps it to the user.
     * @param redeemAmount The amount of the wrapped native token to redeem.
     */
    function redeemNativeToken(uint256 redeemAmount) internal nonReentrant {
        ironBank.redeem(msg.sender, address(this), weth, redeemAmount);
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
            ironBank.repay(address(this), msg.sender, weth, borrowBalance);
            (bool sent,) = msg.sender.call{value: repayAmount - borrowBalance}("");
            require(sent, "failed to send native token");
        } else {
            WethInterface(weth).deposit{value: repayAmount}();
            IERC20(weth).safeIncreaseAllowance(address(ironBank), repayAmount);
            ironBank.repay(address(this), msg.sender, weth, repayAmount);
        }
    }

    /**
     * @notice Supplies the asset to Iron Bank.
     * @param asset The address of the asset to supply.
     * @param amount The amount of the asset to supply.
     */
    function supply(address asset, uint256 amount) internal nonReentrant {
        ironBank.supply(msg.sender, msg.sender, asset, amount);
    }

    /**
     * @notice Borrows the asset from Iron Bank.
     * @param asset The address of the asset to borrow.
     * @param amount The amount of the asset to borrow.
     */
    function borrow(address asset, uint256 amount) internal nonReentrant {
        ironBank.borrow(msg.sender, msg.sender, asset, amount);
    }

    /**
     * @notice Redeems the asset to Iron Bank.
     * @param asset The address of the asset to redeem.
     * @param amount The amount of the asset to redeem.
     */
    function redeem(address asset, uint256 amount) internal nonReentrant {
        ironBank.redeem(msg.sender, msg.sender, asset, amount);
    }

    /**
     * @notice Repays the asset to Iron Bank.
     * @param asset The address of the asset to repay.
     * @param amount The amount of the asset to repay.
     */
    function repay(address asset, uint256 amount) internal nonReentrant {
        ironBank.repay(msg.sender, msg.sender, asset, amount);
    }

    /**
     * @notice Flash exact output swap from Uniswap v3.
     * @param swapOutAsset The address of the swap out asset.
     * @param swapOutAmount The amount of the swap out asset.
     * @param swapInAsset The address of the swap in asset.
     * @param maxSwapInAmount The maximum amount of the swap in asset.
     * @param path The path of the Uniswap v3 swap.
     * @param fee The fee of the Uniswap v3 swap.
     * @param subAction The sub-action for Iron Bank.
     * @param deadline The deadline of the Uniswap v3 swap.
     */
    function uniV3SwapExactOut(
        address swapOutAsset,
        uint256 swapOutAmount,
        address swapInAsset,
        uint256 maxSwapInAmount,
        address[] memory path,
        uint24[] memory fee,
        bytes32 subAction,
        uint256 deadline
    ) internal nonReentrant checkDeadline(deadline) {
        require(swapOutAsset != swapInAsset, "invalid swap out or in asset");
        if (swapOutAmount == type(uint256).max) {
            require(subAction == SUB_ACTION_CLOSE_SHORT_POSITION || subAction == SUB_ACTION_SWAP_DEBT);
            ironBank.accrueInterest(swapOutAsset);
            swapOutAmount = ironBank.getBorrowBalance(msg.sender, swapOutAsset);
        }
        require(swapOutAmount > 0, "invalid swap out amount");
        require(path.length >= 2 && path[0] == swapOutAsset && path[path.length - 1] == swapInAsset, "invalid path");
        require(fee.length == path.length - 1, "invalid fee");

        bytes memory uniV3Path;
        for (uint256 i = 0; i < path.length; i++) {
            uniV3Path = abi.encodePacked(uniV3Path, path[i]);
            if (i != path.length - 1) {
                uniV3Path = abi.encodePacked(uniV3Path, fee[i]);
            }
        }

        uniV3ExactOutputInternal(
            swapOutAmount,
            address(this),
            UniV3SwapData({
                caller: msg.sender,
                swapOutAsset: swapOutAsset,
                swapInAsset: swapInAsset,
                path: uniV3Path,
                subAction: subAction
            })
        );

        uint256 amountIn = uniV3AmountInCached;
        require(amountIn <= maxSwapInAmount, "swap in amount exceeds max swap in amount");
        uniV3AmountInCached = DEFAULT_AMOUNT_CACHED;
    }

    /**
     * @notice Flash exact input swap from Uniswap v3.
     * @param swapInAsset The address of the swap in asset.
     * @param swapInAmount The amount of the swap in asset.
     * @param swapOutAsset The address of the swap out asset.
     * @param minSwapOutAmount The minimum amount of the swap out asset.
     * @param path The path of the Uniswap v3 swap.
     * @param fee The fee of the Uniswap v3 swap.
     * @param subAction The sub-action for Iron Bank.
     * @param deadline The deadline of the Uniswap v3 swap.
     */
    function uniV3SwapExactIn(
        address swapInAsset,
        uint256 swapInAmount,
        address swapOutAsset,
        uint256 minSwapOutAmount,
        address[] memory path,
        uint24[] memory fee,
        bytes32 subAction,
        uint256 deadline
    ) internal nonReentrant checkDeadline(deadline) {
        require(swapInAsset != swapOutAsset, "invalid swap in or out asset");
        if (swapInAmount == type(uint256).max) {
            require(subAction == SUB_ACTION_CLOSE_LONG_POSITION || subAction == SUB_ACTION_SWAP_COLLATERAL);
            ironBank.accrueInterest(swapInAsset);
            swapInAmount = ironBank.getSupplyBalance(msg.sender, swapInAsset);
        }
        require(swapInAmount > 0, "invalid swap in amount");
        require(path.length >= 2 && path[0] == swapInAsset && path[path.length - 1] == swapOutAsset, "invalid path");
        require(fee.length == path.length - 1, "invalid fee");

        bytes memory uniV3Path;
        for (uint256 i = 0; i < path.length; i++) {
            uniV3Path = abi.encodePacked(uniV3Path, path[i]);
            if (i != path.length - 1) {
                uniV3Path = abi.encodePacked(uniV3Path, fee[i]);
            }
        }

        uniV3ExactInputInternal(
            swapInAmount,
            address(this),
            UniV3SwapData({
                caller: msg.sender,
                swapOutAsset: swapOutAsset,
                swapInAsset: swapInAsset,
                path: uniV3Path,
                subAction: subAction
            })
        );

        uint256 amountOut = uniV3AmountOutCached;
        require(amountOut >= minSwapOutAmount, "swap out amount is less than min swap out amount");
        uniV3AmountOutCached = DEFAULT_AMOUNT_CACHED;
    }

    /**
     * @notice Flash exact output swap from Uniswap v2.
     * @param swapOutAsset The address of the swap out asset.
     * @param swapOutAmount The amount of the swap out asset.
     * @param swapInAsset The address of the swap in asset.
     * @param maxSwapInAmount The maximum amount of the swap in asset.
     * @param path The path of the Uniswap v2 swap.
     * @param subAction The sub-action for Iron Bank.
     * @param deadline The deadline of the Uniswap v2 swap.
     */
    function uniV2SwapExactOut(
        address swapOutAsset,
        uint256 swapOutAmount,
        address swapInAsset,
        uint256 maxSwapInAmount,
        address[] memory path,
        bytes32 subAction,
        uint256 deadline
    ) internal nonReentrant checkDeadline(deadline) {
        require(swapOutAsset != swapInAsset, "invalid swap out or in asset");
        if (swapOutAmount == type(uint256).max) {
            require(subAction == SUB_ACTION_CLOSE_SHORT_POSITION || subAction == SUB_ACTION_SWAP_DEBT);
            ironBank.accrueInterest(swapOutAsset);
            swapOutAmount = ironBank.getBorrowBalance(msg.sender, swapOutAsset);
        }
        require(swapOutAmount > 0, "invalid swap out amount");
        require(path.length >= 2 && path[0] == swapOutAsset && path[path.length - 1] == swapInAsset, "invalid path");

        uint256[] memory amounts = UniswapV2Utils.getAmountsIn(uniV2Factory, swapOutAmount, path);

        uniV2ExactOutputInternal(
            UniV2SwapData({
                caller: msg.sender,
                swapOutAsset: swapOutAsset,
                swapInAsset: swapInAsset,
                amounts: amounts,
                path: path,
                index: 0,
                subAction: subAction
            })
        );

        uint256 amountIn = uniV2AmountInCached;
        require(amountIn <= maxSwapInAmount, "swap in amount exceeds max swap in amount");
        uniV2AmountInCached = DEFAULT_AMOUNT_CACHED;
    }

    /**
     * @notice Flash exact input swap from Uniswap v2.
     * @param swapInAsset The address of the swap in asset.
     * @param swapInAmount The amount of the swap in asset.
     * @param swapOutAsset The address of the swap out asset.
     * @param minSwapOutAmount The minimum amount of the swap out asset.
     * @param path The path of the Uniswap v2 swap.
     * @param subAction The sub-action for Iron Bank.
     * @param deadline The deadline of the Uniswap v2 swap.
     */
    function uniV2SwapExactIn(
        address swapInAsset,
        uint256 swapInAmount,
        address swapOutAsset,
        uint256 minSwapOutAmount,
        address[] memory path,
        bytes32 subAction,
        uint256 deadline
    ) internal nonReentrant checkDeadline(deadline) {
        require(swapInAsset != swapOutAsset, "invalid swap in or out asset");
        if (swapInAmount == type(uint256).max) {
            require(subAction == SUB_ACTION_CLOSE_LONG_POSITION || subAction == SUB_ACTION_SWAP_COLLATERAL);
            ironBank.accrueInterest(swapInAsset);
            swapInAmount = ironBank.getSupplyBalance(msg.sender, swapInAsset);
        }
        require(swapInAmount > 0, "invalid swap in amount");
        require(path.length >= 2 && path[0] == swapInAsset && path[path.length - 1] == swapOutAsset, "invalid path");

        uint256[] memory amounts = UniswapV2Utils.getAmountsOut(uniV2Factory, swapInAmount, path);

        uniV2ExactInputInternal(
            UniV2SwapData({
                caller: msg.sender,
                swapOutAsset: swapOutAsset,
                swapInAsset: swapInAsset,
                amounts: amounts,
                path: path,
                index: 0,
                subAction: subAction
            })
        );

        uint256 amountOut = uniV2AmountOutCached;
        require(amountOut >= minSwapOutAmount, "swap out amount is less than min swap out amount");
        uniV2AmountOutCached = DEFAULT_AMOUNT_CACHED;
    }

    /**
     * @notice Exact output swap on Uniswap v3.
     * @param amountOut The amount of the output asset.
     * @param recipient The address to receive the asset.
     * @param data The swap data.
     */
    function uniV3ExactOutputInternal(uint256 amountOut, address recipient, UniV3SwapData memory data)
        private
        returns (uint256 amountIn)
    {
        (address tokenOut, address tokenIn, uint24 fee) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0Delta, int256 amount1Delta) = getUniV3Pool(tokenIn, tokenOut, fee).swap(
            recipient,
            zeroForOne,
            -amountOut.toInt256(),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(data)
        );

        uint256 amountOutReceived;
        (amountIn, amountOutReceived) = zeroForOne
            ? (uint256(amount0Delta), uint256(-amount1Delta))
            : (uint256(amount1Delta), uint256(-amount0Delta));
        require(amountOutReceived == amountOut);
    }

    /**
     * @notice Exact input swap on Uniswap v3.
     * @param amountIn The amount of the input asset.
     * @param recipient The address to receive the asset.
     * @param data The swap data.
     */
    function uniV3ExactInputInternal(uint256 amountIn, address recipient, UniV3SwapData memory data)
        private
        returns (uint256 amountOut)
    {
        (address tokenIn, address tokenOut, uint24 fee) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0, int256 amount1) = getUniV3Pool(tokenIn, tokenOut, fee).swap(
            recipient,
            zeroForOne,
            amountIn.toInt256(),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(data)
        );

        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    /**
     * @notice Exact output swap on Uniswap v2.
     * @param data The swap data.
     */
    function uniV2ExactOutputInternal(UniV2SwapData memory data) private {
        (address tokenA, address tokenB) = (data.path[data.index], data.path[data.index + 1]);

        uint256 amountOut = data.amounts[data.index];

        (uint256 amount0, uint256 amount1) = tokenA < tokenB ? (amountOut, uint256(0)) : (uint256(0), amountOut);

        getUniV2Pool(tokenA, tokenB).swap(amount0, amount1, address(this), abi.encode(data));
    }

    /**
     * @notice Exact input swap on Uniswap v2.
     * @param data The swap data.
     */
    function uniV2ExactInputInternal(UniV2SwapData memory data) private {
        (address tokenA, address tokenB) = (data.path[data.index], data.path[data.index + 1]);

        uint256 amountOut = data.amounts[data.index + 1];

        (uint256 amount0, uint256 amount1) = tokenA < tokenB ? (uint256(0), amountOut) : (amountOut, uint256(0));

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
