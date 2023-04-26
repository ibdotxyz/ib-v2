// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/InterestRateModelInterface.sol";
import "../../interfaces/PriceOracleInterface.sol";
import "../../libraries/DataTypes.sol";
import "../../libraries/PauseFlags.sol";
import "../pool/IronBank.sol";
import "../pool/Constants.sol";

contract IronBankLens is Constants {
    using PauseFlags for DataTypes.MarketConfig;

    struct MarketInfo {
        // market configuration
        bool isListed;
        uint16 collateralFactor;
        uint16 reserveFactor;
        bool supplyPaused;
        bool borrowPaused;
        bool transferPaused;
        bool isSoftDelisted;
        address ibTokenAddress;
        address debtTokenAddress;
        address interestRateModelAddress;
        // market security parameter
        uint256 supplyCap;
        uint256 borrowCap;
        // market current status
        uint256 totalCash;
        uint256 totalBorrow;
        uint256 totalSupply;
        uint256 totalReserves;
        uint256 maxBorrowAmount;
        uint256 marketPrice;
        uint256 exchangeRate;
        uint256 supplyRate;
        uint256 borrowRate;
    }

    function _getMarketInfo(IronBank ironBank, address market, PriceOracleInterface oracle)
        internal
        view
        returns (MarketInfo memory)
    {
        (
            DataTypes.MarketConfig memory config,
            ,
            uint256 totalCash,
            uint256 totalBorrow,
            uint256 totalSupply,
            uint256 totalReserves,
        ) = ironBank.markets(market);

        bool isSoftDelisted =
            config.isSupplyPaused() && config.isBorrowPaused() && config.reserveFactor == MAX_RESERVE_FACTOR;

        InterestRateModelInterface irm = InterestRateModelInterface(config.interestRateModelAddress);

        return MarketInfo({
            isListed: config.isListed,
            collateralFactor: config.collateralFactor,
            reserveFactor: config.reserveFactor,
            supplyPaused: config.isSupplyPaused(),
            borrowPaused: config.isBorrowPaused(),
            transferPaused: config.isTransferPaused(),
            isSoftDelisted: isSoftDelisted,
            ibTokenAddress: config.ibTokenAddress,
            debtTokenAddress: config.debtTokenAddress,
            interestRateModelAddress: config.interestRateModelAddress,
            supplyCap: config.supplyCap,
            borrowCap: config.borrowCap,
            totalCash: totalCash,
            totalBorrow: totalBorrow,
            totalSupply: totalSupply,
            totalReserves: totalReserves,
            maxBorrowAmount: ironBank.getMaxBorrowAmount(market),
            marketPrice: oracle.getPrice(market),
            exchangeRate: ironBank.getExchangeRate(market),
            supplyRate: irm.getSupplyRate(totalCash, totalBorrow),
            borrowRate: irm.getBorrowRate(totalCash, totalBorrow)
        });
    }

    function getMarketInfo(IronBank ironBank, address market) public view returns (MarketInfo memory) {
        PriceOracleInterface oracle = PriceOracleInterface(ironBank.priceOracle());
        return _getMarketInfo(ironBank, market, oracle);
    }

    function getCurrentMarketInfo(IronBank ironBank, address market) public returns (MarketInfo memory) {
        PriceOracleInterface oracle = PriceOracleInterface(ironBank.priceOracle());
        ironBank.accrueInterest(market);
        return _getMarketInfo(ironBank, market, oracle);
    }

    function getAllMarketsInfo(IronBank ironBank) public view returns (MarketInfo[] memory) {
        address[] memory allMarkets = ironBank.getAllMarkets();
        uint256 length = allMarkets.length;

        PriceOracleInterface oracle = PriceOracleInterface(ironBank.priceOracle());

        MarketInfo[] memory marketInfos = new MarketInfo[](length);
        for (uint256 i = 0; i < length; i++) {
            marketInfos[i] = _getMarketInfo(ironBank, allMarkets[i], oracle);
        }
        return marketInfos;
    }

    function getAllCurrentMarketsInfo(IronBank ironBank) public returns (MarketInfo[] memory) {
        address[] memory allMarkets = ironBank.getAllMarkets();
        uint256 length = allMarkets.length;

        PriceOracleInterface oracle = PriceOracleInterface(ironBank.priceOracle());

        MarketInfo[] memory marketInfos = new MarketInfo[](length);
        for (uint256 i = 0; i < length; i++) {
            ironBank.accrueInterest(allMarkets[i]);
            marketInfos[i] = _getMarketInfo(ironBank, allMarkets[i], oracle);
        }
        return marketInfos;
    }

    struct UserMarketInfo {
        address market;
        uint256 exchangeRate;
        uint256 supplyBalance;
        uint256 borrowBalance;
        bool isEnteredMarket;
    }

    function getUserMarketInfo(IronBank ironBank, address user, address market)
        public
        view
        returns (UserMarketInfo memory)
    {
        IERC20 ibToken = IERC20(ironBank.getIBTokenAddress(market));
        uint256 borrowBalance = ironBank.getBorrowBalance(user, market);
        bool isEnteredMarket = ironBank.isEnteredMarket(user, market);

        return UserMarketInfo({
            market: market,
            exchangeRate: ironBank.getExchangeRate(market),
            supplyBalance: ibToken.balanceOf(user),
            borrowBalance: borrowBalance,
            isEnteredMarket: isEnteredMarket
        });
    }

    function getCurrentUserMarketInfo(IronBank ironBank, address user, address market)
        public
        returns (UserMarketInfo memory)
    {
        ironBank.accrueInterest(market);

        IERC20 ibToken = IERC20(ironBank.getIBTokenAddress(market));
        uint256 borrowBalance = ironBank.getBorrowBalance(user, market);
        bool isEnteredMarket = ironBank.isEnteredMarket(user, market);

        return UserMarketInfo({
            market: market,
            exchangeRate: ironBank.getExchangeRate(market),
            supplyBalance: ibToken.balanceOf(user),
            borrowBalance: borrowBalance,
            isEnteredMarket: isEnteredMarket
        });
    }

    function getUserAllMarketsInfo(IronBank ironBank, address user) public view returns (UserMarketInfo[] memory) {
        address[] memory allMarkets = ironBank.getAllMarkets();
        uint256 length = allMarkets.length;

        UserMarketInfo[] memory userMarketInfos = new UserMarketInfo[](length);
        for (uint256 i = 0; i < length; i++) {
            userMarketInfos[i] = getUserMarketInfo(ironBank, user, allMarkets[i]);
        }
        return userMarketInfos;
    }

    function getUserAllCurrentMarketsInfo(IronBank ironBank, address user) public returns (UserMarketInfo[] memory) {
        address[] memory allMarkets = ironBank.getAllMarkets();
        uint256 length = allMarkets.length;

        UserMarketInfo[] memory userMarketInfos = new UserMarketInfo[](length);
        for (uint256 i = 0; i < length; i++) {
            userMarketInfos[i] = getCurrentUserMarketInfo(ironBank, user, allMarkets[i]);
        }
        return userMarketInfos;
    }
}
