// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../protocol/pool/IronBankStorage.sol";

interface IronBankInterface {
    /* ========== USER INTERFACES ========== */

    function enterMarket(address user, address market) external;

    function exitMarket(address user, address market) external;

    function accrueInterest(address market) external;

    function supply(address user, address market, uint256 amount) external;

    function borrow(address user, address asset, uint256 amount) external;

    function redeem(address user, address asset, uint256 amount) external;

    function repay(address user, address asset, uint256 amount) external;

    function deferLiquidityCheck(address user, bytes memory data) external;

    function getBorrowBalance(address user, address market) external view returns (uint256);

    function getMaxBorrowAmount(address market) external view returns (uint256);

    /* ========== TOKEN HOOK INTERFACES ========== */

    function transferIBToken(address market, address from, address to, uint256 amount) external;

    function transferDebt(address market, address from, address to, uint256 amount) external;

    /* ========== MARKET CONFIGURATOR INTERFACES ========== */

    function getMarketConfiguration(address market) external view returns (IronBankStorage.MarketConfig memory);

    function listMarket(address market, IronBankStorage.MarketConfig calldata config) external;

    function delistMarket(address market) external;

    function setMarketConfiguration(address market, IronBankStorage.MarketConfig calldata config) external;

    /* ========== CREDIT LIMIT MANAGER INTERFACES ========== */

    function getCreditLimit(address user, address market) external view returns (uint256);

    function getUserCreditMarkets(address user) external view returns (address[] memory);

    function isCreditAccount(address user) external view returns (bool);

    function setCreditLimit(address user, address market, uint256 credit) external;
}
