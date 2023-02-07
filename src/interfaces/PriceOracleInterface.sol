// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface PriceOracleInterface {
    function getPrice(address asset) external view returns (uint256);
}
