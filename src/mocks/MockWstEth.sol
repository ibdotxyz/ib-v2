// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract MockWstEth is ERC20 {
    uint256 public immutable stEthPerToken;
    IERC20 public immutable stETH;

    constructor(string memory name_, string memory symbol_, address stETH_, uint256 stEthPerToken_) ERC20(name_, symbol_) {
        stEthPerToken = stEthPerToken_;
        stETH = IERC20(stETH_);
    }

    function wrap(uint256 _stETHAmount) external returns (uint256) {
        require(_stETHAmount > 0, "wstETH: can't wrap zero stETH");
        uint256 wstETHAmount = _stETHAmount * 1e18 / stEthPerToken;
        _mint(msg.sender, wstETHAmount);
        stETH.transferFrom(msg.sender, address(this), _stETHAmount);
        return wstETHAmount;
    }

    function unwrap(uint256 _wstETHAmount) external returns (uint256) {
        require(_wstETHAmount > 0, "wstETH: zero amount unwrap not allowed");
        uint256 stETHAmount = _wstETHAmount * stEthPerToken / 1e18;
        _burn(msg.sender, _wstETHAmount);
        stETH.transfer(msg.sender, stETHAmount);
        return stETHAmount;
    }
}
