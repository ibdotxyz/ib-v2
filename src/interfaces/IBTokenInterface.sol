// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IBTokenInterface is IERC20 {
    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;

    function seize(address from, address to, uint256 amount) external;

    function getUnderlying() external view returns (address);
}
