// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ComptrollerV1Interface {
    function isMarketListed(address cTokenAddress) external view returns (bool);

    function checkMembership(address account, address cToken) external view returns (bool);

    function markets(address cToken) external view returns (bool, uint256, uint8);
}
