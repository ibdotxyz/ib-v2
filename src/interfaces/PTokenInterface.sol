// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface PTokenInterface is IERC20 {
    function getUnderlying() external view returns (address);

    function wrap(uint256 amount) external;

    function unwrap(uint256 amount) external;

    function absorb(address user) external;
}
