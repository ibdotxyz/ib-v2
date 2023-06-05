// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBTokenV1Interface {
    function underlying() external view returns (address);

    function getCash() external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function borrowBalanceStored(address account) external view returns (uint256);

    function accrueInterest() external returns (uint256);

    function borrowBalanceCurrent(address account) external returns (uint256);

    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);
}
