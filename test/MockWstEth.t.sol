// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockWstEth is ERC20 {
    uint256 public immutable stEthPerToken;

    constructor(string memory name_, string memory symbol_, uint256 stEthPerToken_) ERC20(name_, symbol_) {
        stEthPerToken = stEthPerToken_;
    }
}
