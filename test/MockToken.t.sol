// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract ERC20Market is ERC20 {
    uint8 private immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, address recipient_)
        ERC20(name_, symbol_)
    {
        _decimals = decimals_;

        _mint(recipient_, 1_000_000_100 * (10 ** _decimals));
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
