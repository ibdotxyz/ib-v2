// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../libraries/DataTypes.sol";

interface IronBankInterface {
    /* ========== USER INTERFACES ========== */

    function accrueInterest(address market) external;

    function supply(address from, address to, address market, uint256 amount) external;

    function borrow(address from, address to, address asset, uint256 amount) external;

    function redeem(address from, address to, address asset, uint256 amount) external;

    function repay(address from, address to, address asset, uint256 amount) external;

    function deferLiquidityCheck(address user, bytes memory data) external;

    function getBorrowBalance(address user, address market) external view returns (uint256);

    function getIBTokenBalance(address user, address market) external view returns (uint256);

    function getSupplyBalance(address user, address market) external view returns (uint256);

    function isMarketListed(address market) external view returns (bool);

    function getTotalSupply(address market) external view returns (uint256);

    function getTotalBorrow(address market) external view returns (uint256);

    function getTotalCash(address market) external view returns (uint256);

    function getTotalReserves(address market) external view returns (uint256);

    function transferIBToken(address market, address from, address to, uint256 amount) external;

    /* ========== MARKET CONFIGURATOR INTERFACES ========== */

    function getMarketConfiguration(address market) external view returns (DataTypes.MarketConfig memory);

    function listMarket(address market, DataTypes.MarketConfig calldata config) external;

    function delistMarket(address market) external;

    function setMarketConfiguration(address market, DataTypes.MarketConfig calldata config) external;

    /* ========== CREDIT LIMIT MANAGER INTERFACES ========== */

    function getCreditLimit(address user, address market) external view returns (uint256);

    function getUserCreditMarkets(address user) external view returns (address[] memory);

    function isCreditAccount(address user) external view returns (bool);

    function setCreditLimit(address user, address market, uint256 credit) external;

    /* ========== RESERVE MANAGER INTERFACES ========== */

    function absorbToReserves(address market) external;

    function reduceReserves(address market, uint256 ibTokenAmount, address recipient) external;
}
