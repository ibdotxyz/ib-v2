// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IronBankInterface.sol";
import "./interfaces/WethInterface.sol";

contract WethExtension {
    IronBankInterface public immutable pool;
    WethInterface public immutable weth;

    constructor(address pool_, address weth_) {
        pool = IronBankInterface(pool_);
        weth = WethInterface(weth_);
        IERC20(weth_).approve(pool_, type(uint256).max);
    }

    function supplyNativeToken() public payable {
        weth.deposit{value: msg.value}();
        pool.supply(msg.sender, address(weth), msg.value);
    }

    function borrowNativeToken(uint256 borrowAmount) public {
        pool.borrow(msg.sender, address(weth), borrowAmount);
        weth.withdraw(borrowAmount);
        (bool sent,) = msg.sender.call{value: borrowAmount}("");
        require(sent, "failed to send native token");
    }

    function redeemNativeToken(uint256 redeemAmount) public {
        pool.redeem(msg.sender, address(weth), redeemAmount);
        weth.withdraw(redeemAmount);
        (bool sent,) = msg.sender.call{value: redeemAmount}("");
        require(sent, "failed to send native token");
    }

    function repayNativeToken() public payable {
        uint256 repayAmount = msg.value;

        pool.accrueInterest(address(weth));
        uint256 borrowBalance = pool.getBorrowBalance(msg.sender, address(weth));
        if (repayAmount > borrowBalance) {
            weth.deposit{value: borrowBalance}();
            pool.repay(msg.sender, address(weth), borrowBalance);
            (bool sent,) = msg.sender.call{value: repayAmount - borrowBalance}("");
            require(sent, "failed to send native token");
        } else {
            weth.deposit{value: repayAmount}();
            pool.repay(msg.sender, address(weth), repayAmount);
        }
    }

    receive() external payable {}
}
