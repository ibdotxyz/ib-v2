// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface InterestRateModelInterface {
    function getUtilization(uint256 cash, uint256 borrow) external pure returns (uint256);

    function getBorrowRate(uint256 cash, uint256 borrow) external view returns (uint256);

    function getSupplyRate(uint256 cash, uint256 borrow) external view returns (uint256);
}
