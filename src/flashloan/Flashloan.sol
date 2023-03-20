// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IERC3156FlashLender.sol";
import "../interfaces/DeferLiquidityCheckInterface.sol";
import "../interfaces/IronBankInterface.sol";

contract Flashloan is IERC3156FlashLender, DeferLiquidityCheckInterface {
    using SafeERC20 for IERC20;

    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    address private immutable _pool;

    bool internal _isDeferredLiquidityCheck;

    constructor(address pool_) {
        _pool = pool_;
    }

    function maxFlashLoan(address token) external view override returns (uint256) {
        if (!IronBankInterface(_pool).isMarketListed(token)) {
            return 0;
        }

        return IronBankInterface(_pool).getMaxBorrowAmount(token);
    }

    function flashFee(address token, uint256 amount) external view override returns (uint256) {
        amount;

        require(IronBankInterface(_pool).isMarketListed(token), "token not listed");

        return 0;
    }

    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external
        override
        returns (bool)
    {
        require(IronBankInterface(_pool).isMarketListed(token), "token not listed");

        if (!_isDeferredLiquidityCheck) {
            IronBankInterface(_pool).deferLiquidityCheck(
                address(this), abi.encode(receiver, token, amount, data, msg.sender)
            );
            _isDeferredLiquidityCheck = false;
        } else {
            _loan(receiver, token, amount, data, msg.sender);
        }

        return true;
    }

    function onDeferredLiquidityCheck(bytes memory encodedData) external override {
        require(msg.sender == _pool, "untrusted message sender");
        (IERC3156FlashBorrower receiver, address token, uint256 amount, bytes memory data, address msgSender) =
            abi.decode(encodedData, (IERC3156FlashBorrower, address, uint256, bytes, address));

        _isDeferredLiquidityCheck = true;
        _loan(receiver, token, amount, data, msgSender);
    }

    function _loan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes memory data, address msgSender)
        internal
    {
        IronBankInterface(_pool).borrow(address(this), token, amount);
        IERC20(token).safeTransfer(address(receiver), amount);

        require(receiver.onFlashLoan(msgSender, token, amount, 0, data) == CALLBACK_SUCCESS, "callback failed");

        IERC20(token).safeTransferFrom(address(receiver), address(this), amount);
        require(IERC20(token).balanceOf(address(this)) >= amount, "insufficient repay amount");

        uint256 allowance = IERC20(token).allowance(address(this), _pool);
        if (allowance < amount) {
            IERC20(token).safeApprove(_pool, type(uint256).max);
        }

        IronBankInterface(_pool).repay(address(this), token, amount);
    }
}
