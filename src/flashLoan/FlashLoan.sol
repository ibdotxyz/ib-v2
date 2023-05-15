// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IERC3156FlashLender.sol";
import "../interfaces/DeferLiquidityCheckInterface.sol";
import "../interfaces/IronBankInterface.sol";

contract FlashLoan is IERC3156FlashLender, DeferLiquidityCheckInterface {
    using SafeERC20 for IERC20;

    /// @notice The standard signature for ERC-3156 borrower
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /// @notice The Iron Bank contract
    address public immutable ironBank;

    /// @dev The deferred liquidity check flag
    bool internal _isDeferredLiquidityCheck;

    constructor(address ironBank_) {
        ironBank = ironBank_;
    }

    /// @inheritdoc IERC3156FlashLender
    function maxFlashLoan(address token) external view override returns (uint256) {
        if (!IronBankInterface(ironBank).isMarketListed(token)) {
            return 0;
        }

        DataTypes.MarketConfig memory config = IronBankInterface(ironBank).getMarketConfiguration(token);
        uint256 totalCash = IronBankInterface(ironBank).getTotalCash(token);
        uint256 totalBorrow = IronBankInterface(ironBank).getTotalBorrow(token);

        uint256 maxBorrowAmount;
        if (config.borrowCap == 0) {
            maxBorrowAmount = totalCash;
        } else if (config.borrowCap > totalBorrow) {
            uint256 gap = config.borrowCap - totalBorrow;
            maxBorrowAmount = gap < totalCash ? gap : totalCash;
        }

        return maxBorrowAmount;
    }

    /// @inheritdoc IERC3156FlashLender
    function flashFee(address token, uint256 amount) external view override returns (uint256) {
        amount;

        require(IronBankInterface(ironBank).isMarketListed(token), "token not listed");

        return 0;
    }

    /// @inheritdoc IERC3156FlashLender
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external
        override
        returns (bool)
    {
        require(IronBankInterface(ironBank).isMarketListed(token), "token not listed");

        if (!_isDeferredLiquidityCheck) {
            IronBankInterface(ironBank).deferLiquidityCheck(
                address(this), abi.encode(receiver, token, amount, data, msg.sender)
            );
            _isDeferredLiquidityCheck = false;
        } else {
            _loan(receiver, token, amount, data, msg.sender);
        }

        return true;
    }

    /// @inheritdoc DeferLiquidityCheckInterface
    function onDeferredLiquidityCheck(bytes memory encodedData) external override {
        require(msg.sender == ironBank, "untrusted message sender");
        (IERC3156FlashBorrower receiver, address token, uint256 amount, bytes memory data, address msgSender) =
            abi.decode(encodedData, (IERC3156FlashBorrower, address, uint256, bytes, address));

        _isDeferredLiquidityCheck = true;
        _loan(receiver, token, amount, data, msgSender);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Flash borrow from Iron Bank to the receiver.
     * @param receiver The receiver of the flash loan
     * @param token The token to borrow
     * @param amount The amount to borrow
     * @param data Arbitrary data that is passed to the receiver
     * @param msgSender The original caller
     */
    function _loan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes memory data, address msgSender)
        internal
    {
        IronBankInterface(ironBank).borrow(address(this), address(receiver), token, amount);

        require(receiver.onFlashLoan(msgSender, token, amount, 0, data) == CALLBACK_SUCCESS, "callback failed"); // no fee

        IERC20(token).safeTransferFrom(address(receiver), address(this), amount);

        uint256 allowance = IERC20(token).allowance(address(this), ironBank);
        if (allowance < amount) {
            IERC20(token).safeApprove(ironBank, type(uint256).max);
        }

        IronBankInterface(ironBank).repay(address(this), address(this), token, amount);
    }
}
