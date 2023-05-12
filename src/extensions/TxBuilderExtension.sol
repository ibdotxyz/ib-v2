// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/DeferLiquidityCheckInterface.sol";
import "../interfaces/IronBankInterface.sol";
import "../interfaces/PTokenInterface.sol";
import "./interfaces/WethInterface.sol";
import "./interfaces/WstEthInterface.sol";

contract TxBuilderExtension is ReentrancyGuard, Ownable2Step, DeferLiquidityCheckInterface {
    using SafeERC20 for IERC20;

    /// @notice The action for deferring liquidity check
    bytes32 public constant ACTION_DEFER_LIQUIDITY_CHECK = "ACTION_DEFER_LIQUIDITY_CHECK";

    /// @notice The action for supplying asset
    bytes32 public constant ACTION_SUPPLY = "ACTION_SUPPLY";

    /// @notice The action for borrowing asset
    bytes32 public constant ACTION_BORROW = "ACTION_BORROW";

    /// @notice The action for redeeming asset
    bytes32 public constant ACTION_REDEEM = "ACTION_REDEEM";

    /// @notice The action for repaying asset
    bytes32 public constant ACTION_REPAY = "ACTION_REPAY";

    /// @notice The action for supplying native token
    bytes32 public constant ACTION_SUPPLY_NATIVE_TOKEN = "ACTION_SUPPLY_NATIVE_TOKEN";

    /// @notice The action for borrowing native token
    bytes32 public constant ACTION_BORROW_NATIVE_TOKEN = "ACTION_BORROW_NATIVE_TOKEN";

    /// @notice The action for redeeming native token
    bytes32 public constant ACTION_REDEEM_NATIVE_TOKEN = "ACTION_REDEEM_NATIVE_TOKEN";

    /// @notice The action for repaying native token
    bytes32 public constant ACTION_REPAY_NATIVE_TOKEN = "ACTION_REPAY_NATIVE_TOKEN";

    /// @notice The action for supplying stEth
    bytes32 public constant ACTION_SUPPLY_STETH = "ACTION_SUPPLY_STETH";

    /// @notice The action for borrowing stEth
    bytes32 public constant ACTION_BORROW_STETH = "ACTION_BORROW_STETH";

    /// @notice The action for redeeming stEth
    bytes32 public constant ACTION_REDEEM_STETH = "ACTION_REDEEM_STETH";

    /// @notice The action for repaying stEth
    bytes32 public constant ACTION_REPAY_STETH = "ACTION_REPAY_STETH";

    /// @notice The action for supplying pToken
    bytes32 public constant ACTION_SUPPLY_PTOKEN = "ACTION_SUPPLY_PTOKEN";

    /// @notice The action for redeeming pToken
    bytes32 public constant ACTION_REDEEM_PTOKEN = "ACTION_REDEEM_PTOKEN";

    /// @notice The address of IronBank
    IronBankInterface public immutable ironBank;

    /// @notice The address of WETH
    address public immutable weth;

    /// @notice The address of Lido staked ETH
    address public immutable steth;

    /// @notice The address of Lido wrapped staked ETH
    address public immutable wsteth;

    /**
     * @notice Construct a new TxBuilderExtension contract
     * @param ironBank_ The IronBank contract
     * @param weth_ The WETH contract
     * @param steth_ The Lido staked ETH contract
     * @param wsteth_ The Lido wrapped staked ETH contract
     */
    constructor(address ironBank_, address weth_, address steth_, address wsteth_) {
        ironBank = IronBankInterface(ironBank_);
        weth = weth_;
        steth = steth_;
        wsteth = wsteth_;
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
        executeInternal(msg.sender, actions, 0);
    }

    /// @inheritdoc DeferLiquidityCheckInterface
    function onDeferredLiquidityCheck(bytes memory encodedData) external override {
        require(msg.sender == address(ironBank), "untrusted message sender");

        (address initiator, Action[] memory actions, uint256 index) =
            abi.decode(encodedData, (address, Action[], uint256));
        executeInternal(initiator, actions, index);
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
     * @dev Execute a list of actions for user in order.
     * @param user The address of the user
     * @param actions The list of actions
     * @param index The index of the action to start with
     */
    function executeInternal(address user, Action[] memory actions, uint256 index) internal {
        for (uint256 i = index; i < actions.length;) {
            Action memory action = actions[i];
            if (action.name == ACTION_DEFER_LIQUIDITY_CHECK) {
                deferLiquidityCheck(user, abi.encode(user, actions, i + 1));

                // Break the loop as we will re-enter the loop after the liquidity check is deferred.
                break;
            } else if (action.name == ACTION_SUPPLY) {
                (address asset, uint256 amount) = abi.decode(action.data, (address, uint256));
                supply(user, asset, amount);
            } else if (action.name == ACTION_BORROW) {
                (address asset, uint256 amount) = abi.decode(action.data, (address, uint256));
                borrow(user, asset, amount);
            } else if (action.name == ACTION_REDEEM) {
                (address asset, uint256 amount) = abi.decode(action.data, (address, uint256));
                redeem(user, asset, amount);
            } else if (action.name == ACTION_REPAY) {
                (address asset, uint256 amount) = abi.decode(action.data, (address, uint256));
                repay(user, asset, amount);
            } else if (action.name == ACTION_SUPPLY_NATIVE_TOKEN) {
                supplyNativeToken(user);
            } else if (action.name == ACTION_BORROW_NATIVE_TOKEN) {
                uint256 borrowAmount = abi.decode(action.data, (uint256));
                borrowNativeToken(user, borrowAmount);
            } else if (action.name == ACTION_REDEEM_NATIVE_TOKEN) {
                uint256 redeemAmount = abi.decode(action.data, (uint256));
                redeemNativeToken(user, redeemAmount);
            } else if (action.name == ACTION_REPAY_NATIVE_TOKEN) {
                repayNativeToken(user);
            } else if (action.name == ACTION_SUPPLY_STETH) {
                uint256 amount = abi.decode(action.data, (uint256));
                supplyStEth(user, amount);
            } else if (action.name == ACTION_BORROW_STETH) {
                uint256 amount = abi.decode(action.data, (uint256));
                borrowStEth(user, amount);
            } else if (action.name == ACTION_REDEEM_STETH) {
                uint256 amount = abi.decode(action.data, (uint256));
                redeemStEth(user, amount);
            } else if (action.name == ACTION_REPAY_STETH) {
                uint256 amount = abi.decode(action.data, (uint256));
                repayStEth(user, amount);
            } else if (action.name == ACTION_SUPPLY_PTOKEN) {
                (address pToken, uint256 amount) = abi.decode(action.data, (address, uint256));
                supplyPToken(user, pToken, amount);
            } else if (action.name == ACTION_REDEEM_PTOKEN) {
                (address pToken, uint256 amount) = abi.decode(action.data, (address, uint256));
                redeemPToken(user, pToken, amount);
            } else {
                revert("invalid action");
            }

            unchecked {
                i++;
            }
        }
    }

    /**
     * @dev Defers the liquidity check.
     * @param user The address of the user
     * @param data The encoded data
     */
    function deferLiquidityCheck(address user, bytes memory data) internal {
        ironBank.deferLiquidityCheck(user, data);
    }

    /**
     * @dev Supplies the asset to Iron Bank.
     * @param user The address of the user
     * @param asset The address of the asset to supply
     * @param amount The amount of the asset to supply
     */
    function supply(address user, address asset, uint256 amount) internal nonReentrant {
        ironBank.supply(user, user, asset, amount);
    }

    /**
     * @dev Borrows the asset from Iron Bank.
     * @param user The address of the user
     * @param asset The address of the asset to borrow
     * @param amount The amount of the asset to borrow
     */
    function borrow(address user, address asset, uint256 amount) internal nonReentrant {
        ironBank.borrow(user, user, asset, amount);
    }

    /**
     * @dev Redeems the asset to Iron Bank.
     * @param user The address of the user
     * @param asset The address of the asset to redeem
     * @param amount The amount of the asset to redeem
     */
    function redeem(address user, address asset, uint256 amount) internal nonReentrant {
        ironBank.redeem(user, user, asset, amount);
    }

    /**
     * @dev Repays the asset to Iron Bank.
     * @param user The address of the user
     * @param asset The address of the asset to repay
     * @param amount The amount of the asset to repay
     */
    function repay(address user, address asset, uint256 amount) internal nonReentrant {
        ironBank.repay(user, user, asset, amount);
    }

    /**
     * @dev Wraps the native token and supplies it to Iron Bank.
     * @param user The address of the user
     */
    function supplyNativeToken(address user) internal nonReentrant {
        WethInterface(weth).deposit{value: msg.value}();
        IERC20(weth).safeIncreaseAllowance(address(ironBank), msg.value);
        ironBank.supply(address(this), user, weth, msg.value);
    }

    /**
     * @dev Borrows the wrapped native token and unwraps it to the user.
     * @param user The address of the user
     * @param borrowAmount The amount of the wrapped native token to borrow
     */
    function borrowNativeToken(address user, uint256 borrowAmount) internal nonReentrant {
        ironBank.borrow(user, address(this), weth, borrowAmount);
        WethInterface(weth).withdraw(borrowAmount);
        (bool sent,) = user.call{value: borrowAmount}("");
        require(sent, "failed to send native token");
    }

    /**
     * @dev Redeems the wrapped native token and unwraps it to the user.
     * @param user The address of the user
     * @param redeemAmount The amount of the wrapped native token to redeem, -1 means redeem all
     */
    function redeemNativeToken(address user, uint256 redeemAmount) internal nonReentrant {
        if (redeemAmount == type(uint256).max) {
            redeemAmount = ironBank.getSupplyBalance(user, weth);
        }
        ironBank.redeem(user, address(this), weth, redeemAmount);
        WethInterface(weth).withdraw(redeemAmount);
        (bool sent,) = user.call{value: redeemAmount}("");
        require(sent, "failed to send native token");
    }

    /**
     * @dev Wraps the native token and repays it to Iron Bank.
     * @dev If the amount of the native token is greater than the borrow balance, the excess amount will be sent back to the user.
     * @param user The address of the user
     */
    function repayNativeToken(address user) internal nonReentrant {
        uint256 repayAmount = msg.value;

        ironBank.accrueInterest(weth);
        uint256 borrowBalance = ironBank.getBorrowBalance(user, weth);
        if (repayAmount > borrowBalance) {
            WethInterface(weth).deposit{value: borrowBalance}();
            IERC20(weth).safeIncreaseAllowance(address(ironBank), borrowBalance);
            ironBank.repay(address(this), user, weth, borrowBalance);
            (bool sent,) = user.call{value: repayAmount - borrowBalance}("");
            require(sent, "failed to send native token");
        } else {
            WethInterface(weth).deposit{value: repayAmount}();
            IERC20(weth).safeIncreaseAllowance(address(ironBank), repayAmount);
            ironBank.repay(address(this), user, weth, repayAmount);
        }
    }

    /**
     * @dev Wraps the stEth and supplies wstEth to Iron Bank.
     * @param user The address of the user
     * @param stEthAmount The amount of the stEth to supply
     */
    function supplyStEth(address user, uint256 stEthAmount) internal nonReentrant {
        IERC20(steth).safeTransferFrom(user, address(this), stEthAmount);
        IERC20(steth).safeIncreaseAllowance(wsteth, stEthAmount);
        uint256 wstEthAmount = WstEthInterface(wsteth).wrap(stEthAmount);
        IERC20(wsteth).safeIncreaseAllowance(address(ironBank), wstEthAmount);
        ironBank.supply(address(this), user, wsteth, wstEthAmount);
    }

    /**
     * @dev Borrows the wstEth and unwraps it to the user.
     * @param user The address of the user
     * @param stEthAmount The amount of the stEth to borrow
     */
    function borrowStEth(address user, uint256 stEthAmount) internal nonReentrant {
        uint256 wstEthAmount = WstEthInterface(wsteth).getWstETHByStETH(stEthAmount);
        ironBank.borrow(user, address(this), wsteth, wstEthAmount);
        uint256 unwrappedStEthAmount = WstEthInterface(wsteth).unwrap(wstEthAmount);
        IERC20(steth).safeTransfer(user, unwrappedStEthAmount);
    }

    /**
     * @dev Redeems the wstEth and unwraps it to the user.
     * @param user The address of the user
     * @param stEthAmount The amount of the stEth to redeem, -1 means redeem all
     */
    function redeemStEth(address user, uint256 stEthAmount) internal nonReentrant {
        uint256 wstEthAmount;
        if (stEthAmount == type(uint256).max) {
            ironBank.accrueInterest(wsteth);
            wstEthAmount = ironBank.getSupplyBalance(user, wsteth);
        } else {
            wstEthAmount = WstEthInterface(wsteth).getWstETHByStETH(stEthAmount);
        }
        ironBank.redeem(user, address(this), wsteth, wstEthAmount);
        uint256 unwrappedStEthAmount = WstEthInterface(wsteth).unwrap(wstEthAmount);
        IERC20(steth).safeTransfer(user, unwrappedStEthAmount);
    }

    /**
     * @dev Wraps the stEth and repays wstEth to Iron Bank.
     * @param user The address of the user
     * @param stEthAmount The amount of the stEth to repay, -1 means repay all
     */
    function repayStEth(address user, uint256 stEthAmount) internal nonReentrant {
        if (stEthAmount == type(uint256).max) {
            ironBank.accrueInterest(wsteth);
            uint256 borrowBalance = ironBank.getBorrowBalance(user, wsteth);
            stEthAmount = WstEthInterface(wsteth).getStETHByWstETH(borrowBalance) + 1; // add 1 to avoid rounding issue
        }

        IERC20(steth).safeTransferFrom(user, address(this), stEthAmount);
        IERC20(steth).safeIncreaseAllowance(wsteth, stEthAmount);
        uint256 wstEthAmount = WstEthInterface(wsteth).wrap(stEthAmount);
        IERC20(wsteth).safeIncreaseAllowance(address(ironBank), wstEthAmount);
        ironBank.repay(address(this), user, wsteth, wstEthAmount);
    }

    /**
     * @dev Wraps the underlying and supplies the pToken to Iron Bank.
     * @param user The address of the user
     * @param pToken The address of the pToken
     * @param amount The amount of the pToken to supply
     */
    function supplyPToken(address user, address pToken, uint256 amount) internal nonReentrant {
        address underlying = PTokenInterface(pToken).getUnderlying();
        IERC20(underlying).safeTransferFrom(user, pToken, amount);
        PTokenInterface(pToken).absorb(address(this));
        IERC20(pToken).safeIncreaseAllowance(address(ironBank), amount);
        ironBank.supply(address(this), user, pToken, amount);
    }

    /**
     * @dev Redeems the pToken and unwraps the underlying to the user.
     * @param user The address of the user
     * @param pToken The address of the pToken
     * @param amount The amount of the pToken to redeem
     */
    function redeemPToken(address user, address pToken, uint256 amount) internal nonReentrant {
        if (amount == type(uint256).max) {
            ironBank.accrueInterest(pToken);
            amount = ironBank.getSupplyBalance(user, pToken);
        }
        ironBank.redeem(user, address(this), pToken, amount);
        PTokenInterface(pToken).unwrap(amount);
        address underlying = PTokenInterface(pToken).getUnderlying();
        IERC20(underlying).safeTransfer(user, amount);
    }

    receive() external payable {}
}
