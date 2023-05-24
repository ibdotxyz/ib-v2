// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBTokenInterface {
    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;

    function seize(address from, address to, uint256 amount) external;

    function asset() external view returns (address);
}
