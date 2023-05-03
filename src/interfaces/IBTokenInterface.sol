// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IBTokenInterface is IERC20, IERC20Metadata {
    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;

    function seize(address from, address to, uint256 amount) external;

    function asset() external view returns (address);
}
