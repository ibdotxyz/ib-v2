// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../interfaces/InterestRateModelInterface.sol";
import "../../interfaces/PriceOracleInterface.sol";
import "../../libraries/DataTypes.sol";
import "../../libraries/PauseFlags.sol";
import "../pool/IronBank.sol";
import "../pool/Constants.sol";

contract IronBankLens is Constants {
    using PauseFlags for DataTypes.MarketConfig;

    struct MarketMetadata {
        address market;
        string marketName;
        string marketSymbol;
        uint8 marketDecimals;
        bool isListed;
        uint16 collateralFactor;
        uint16 liquidationThreshold;
        uint16 liquidationBonus;
        uint16 reserveFactor;
        bool isPToken;
        bool supplyPaused;
        bool borrowPaused;
        bool transferPaused;
        bool isSoftDelisted;
        address ibTokenAddress;
        address debtTokenAddress;
        address pTokenAddress;
        address interestRateModelAddress;
        uint256 supplyCap;
        uint256 borrowCap;
    }

    struct MarketStatus {
        address market;
        uint256 totalCash;
        uint256 totalBorrow;
        uint256 totalSupply;
        uint256 totalReserves;
        uint256 maxSupplyAmount;
        uint256 maxBorrowAmount;
        uint256 marketPrice;
        uint256 exchangeRate;
        uint256 supplyRate;
        uint256 borrowRate;
    }

    struct UserMarketStatus {
        address market;
        uint256 balance;
        uint256 allowanceToIronBank;
        uint256 exchangeRate;
        uint256 ibTokenBalance;
        uint256 supplyBalance;
        uint256 borrowBalance;
    }

    /**
     * @notice Gets the market metadata for a given market.
     * @param ironBank The Iron Bank contract
     * @param market The market to get metadata for
     * @return The market metadata
     */
    function getMarketMetadata(IronBank ironBank, address market) public view returns (MarketMetadata memory) {
        return _getMarketMetadata(ironBank, market);
    }

    /**
     * @notice Gets the market metadata for all markets.
     * @param ironBank The Iron Bank contract
     * @return The list of all market metadata
     */
    function getAllMarketsMetadata(IronBank ironBank) public view returns (MarketMetadata[] memory) {
        address[] memory markets = ironBank.getAllMarkets();
        MarketMetadata[] memory configs = new MarketMetadata[](markets.length);
        for (uint256 i = 0; i < markets.length; i++) {
            configs[i] = _getMarketMetadata(ironBank, markets[i]);
        }
        return configs;
    }

    /**
     * @notice Gets the market status for a given market.
     * @param ironBank The Iron Bank contract
     * @param market The market to get status for
     * @return The market status
     */
    function getMarketStatus(IronBank ironBank, address market) public view returns (MarketStatus memory) {
        PriceOracleInterface oracle = PriceOracleInterface(ironBank.priceOracle());
        return _getMarketStatus(ironBank, market, oracle);
    }

    /**
     * @notice Gets the current market status for a given market.
     * @dev This function is not gas efficient and should _not_ be called on chain.
     * @param ironBank The Iron Bank contract
     * @param market The market to get status for
     * @return The market status
     */
    function getCurrentMarketStatus(IronBank ironBank, address market) public returns (MarketStatus memory) {
        PriceOracleInterface oracle = PriceOracleInterface(ironBank.priceOracle());
        ironBank.accrueInterest(market);
        return _getMarketStatus(ironBank, market, oracle);
    }

    /**
     * @notice Gets the market status for all markets.
     * @param ironBank The Iron Bank contract
     * @return The list of all market status
     */
    function getAllMarketsStatus(IronBank ironBank) public view returns (MarketStatus[] memory) {
        address[] memory allMarkets = ironBank.getAllMarkets();
        uint256 length = allMarkets.length;

        PriceOracleInterface oracle = PriceOracleInterface(ironBank.priceOracle());

        MarketStatus[] memory marketStatus = new MarketStatus[](length);
        for (uint256 i = 0; i < length; i++) {
            marketStatus[i] = _getMarketStatus(ironBank, allMarkets[i], oracle);
        }
        return marketStatus;
    }

    /**
     * @notice Gets the current market status for all markets.
     * @dev This function is not gas efficient and should _not_ be called on chain.
     * @param ironBank The Iron Bank contract
     * @return The list of all market status
     */
    function getAllCurrentMarketsStatus(IronBank ironBank) public returns (MarketStatus[] memory) {
        address[] memory allMarkets = ironBank.getAllMarkets();
        uint256 length = allMarkets.length;

        PriceOracleInterface oracle = PriceOracleInterface(ironBank.priceOracle());

        MarketStatus[] memory marketStatus = new MarketStatus[](length);
        for (uint256 i = 0; i < length; i++) {
            ironBank.accrueInterest(allMarkets[i]);
            marketStatus[i] = _getMarketStatus(ironBank, allMarkets[i], oracle);
        }
        return marketStatus;
    }

    /**
     * @notice Gets the user's market status for a given market.
     * @param ironBank The Iron Bank contract
     * @param user The user to get status for
     * @param market The market to get status for
     * @return The user's market status
     */
    function getUserMarketStatus(IronBank ironBank, address user, address market)
        public
        view
        returns (UserMarketStatus memory)
    {
        return UserMarketStatus({
            market: market,
            balance: IERC20(market).balanceOf(user),
            allowanceToIronBank: IERC20(market).allowance(user, address(ironBank)),
            exchangeRate: ironBank.getExchangeRate(market),
            ibTokenBalance: ironBank.getIBTokenBalance(user, market),
            supplyBalance: ironBank.getSupplyBalance(user, market),
            borrowBalance: ironBank.getBorrowBalance(user, market)
        });
    }

    /**
     * @notice Gets the user's current market status for a given market.
     * @dev This function is not gas efficient and should _not_ be called on chain.
     * @param ironBank The Iron Bank contract
     * @param user The user to get status for
     * @param market The market to get status for
     * @return The user's market status
     */
    function getCurrentUserMarketStatus(IronBank ironBank, address user, address market)
        public
        returns (UserMarketStatus memory)
    {
        ironBank.accrueInterest(market);

        return UserMarketStatus({
            market: market,
            balance: IERC20(market).balanceOf(user),
            allowanceToIronBank: IERC20(market).allowance(user, address(ironBank)),
            exchangeRate: ironBank.getExchangeRate(market),
            ibTokenBalance: ironBank.getIBTokenBalance(user, market),
            supplyBalance: ironBank.getSupplyBalance(user, market),
            borrowBalance: ironBank.getBorrowBalance(user, market)
        });
    }

    /**
     * @notice Gets the user's market status for all markets.
     * @param ironBank The Iron Bank contract
     * @param user The user to get status for
     * @return The list of all user's market status
     */
    function getUserAllMarketsStatus(IronBank ironBank, address user) public view returns (UserMarketStatus[] memory) {
        address[] memory allMarkets = ironBank.getAllMarkets();
        uint256 length = allMarkets.length;

        UserMarketStatus[] memory userMarketStatus = new UserMarketStatus[](length);
        for (uint256 i = 0; i < length; i++) {
            userMarketStatus[i] = getUserMarketStatus(ironBank, user, allMarkets[i]);
        }
        return userMarketStatus;
    }

    /**
     * @notice Gets the user's current market status for all markets.
     * @dev This function is not gas efficient and should _not_ be called on chain.
     * @param ironBank The Iron Bank contract
     * @param user The user to get status for
     * @return The list of all user's market status
     */
    function getUserAllCurrentMarketsStatus(IronBank ironBank, address user)
        public
        returns (UserMarketStatus[] memory)
    {
        address[] memory allMarkets = ironBank.getAllMarkets();
        uint256 length = allMarkets.length;

        UserMarketStatus[] memory userMarketStatus = new UserMarketStatus[](length);
        for (uint256 i = 0; i < length; i++) {
            userMarketStatus[i] = getCurrentUserMarketStatus(ironBank, user, allMarkets[i]);
        }
        return userMarketStatus;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Gets the market metadata for a given market.
     * @param ironBank The Iron Bank contract
     * @param market The market to get metadata for
     * @return The market metadata
     */
    function _getMarketMetadata(IronBank ironBank, address market) internal view returns (MarketMetadata memory) {
        DataTypes.MarketConfig memory config = ironBank.getMarketConfiguration(market);
        bool isSoftDelisted =
            config.isSupplyPaused() && config.isBorrowPaused() && config.reserveFactor == MAX_RESERVE_FACTOR;
        return MarketMetadata({
            market: market,
            marketName: IERC20Metadata(market).name(),
            marketSymbol: IERC20Metadata(market).symbol(),
            marketDecimals: IERC20Metadata(market).decimals(),
            isListed: config.isListed,
            collateralFactor: config.collateralFactor,
            liquidationThreshold: config.liquidationThreshold,
            liquidationBonus: config.liquidationBonus,
            reserveFactor: config.reserveFactor,
            isPToken: config.isPToken,
            supplyPaused: config.isSupplyPaused(),
            borrowPaused: config.isBorrowPaused(),
            transferPaused: config.isTransferPaused(),
            isSoftDelisted: isSoftDelisted,
            ibTokenAddress: config.ibTokenAddress,
            debtTokenAddress: config.debtTokenAddress,
            pTokenAddress: config.pTokenAddress,
            interestRateModelAddress: config.interestRateModelAddress,
            supplyCap: config.supplyCap,
            borrowCap: config.borrowCap
        });
    }

    /**
     * @dev Gets the market status for a given market.
     * @param ironBank The Iron Bank contract
     * @param market The market to get status for
     * @param oracle The price oracle contract
     * @return The market status
     */
    function _getMarketStatus(IronBank ironBank, address market, PriceOracleInterface oracle)
        internal
        view
        returns (MarketStatus memory)
    {
        DataTypes.MarketConfig memory config = ironBank.getMarketConfiguration(market);
        uint256 totalCash = ironBank.getTotalCash(market);
        uint256 totalBorrow = ironBank.getTotalBorrow(market);
        uint256 totalSupply = ironBank.getTotalSupply(market);
        uint256 totalReserves = ironBank.getTotalReserves(market);

        InterestRateModelInterface irm = InterestRateModelInterface(config.interestRateModelAddress);

        uint256 totalSupplyUnderlying = totalSupply * ironBank.getExchangeRate(market) / 1e18;
        uint256 maxSupplyAmount;
        if (config.supplyCap == 0) {
            maxSupplyAmount = type(uint256).max;
        } else if (config.supplyCap > totalSupplyUnderlying) {
            maxSupplyAmount = config.supplyCap - totalSupplyUnderlying;
        }

        uint256 maxBorrowAmount;
        if (config.borrowCap == 0) {
            maxBorrowAmount = totalCash;
        } else if (config.borrowCap > totalBorrow) {
            uint256 gap = config.borrowCap - totalBorrow;
            maxBorrowAmount = gap < totalCash ? gap : totalCash;
        }

        return MarketStatus({
            market: market,
            totalCash: totalCash,
            totalBorrow: totalBorrow,
            totalSupply: totalSupply,
            totalReserves: totalReserves,
            maxSupplyAmount: maxSupplyAmount,
            maxBorrowAmount: maxBorrowAmount,
            marketPrice: oracle.getPrice(market),
            exchangeRate: ironBank.getExchangeRate(market),
            supplyRate: irm.getSupplyRate(totalCash, totalBorrow),
            borrowRate: irm.getBorrowRate(totalCash, totalBorrow)
        });
    }
}
