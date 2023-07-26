// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IronBankInterface.sol";
import "../interfaces/PriceOracleInterface.sol";
import "../libraries/PauseFlags.sol";
import "./interfaces/ComptrollerV1Interface.sol";
import "./interfaces/IBTokenV1Interface.sol";

// priceOracle() is not in the interface but it is in the storage.
interface IronBankInterfaceForMigration is IronBankInterface {
    function priceOracle() external view returns (address);
}

contract MigrationExtensionLens {
    using SafeERC20 for IERC20;
    using PauseFlags for DataTypes.MarketConfig;

    /// @notice The address of IronBank v2
    IronBankInterfaceForMigration public immutable ironBank;

    /// @notice The address of IronBank v2 price oracle
    PriceOracleInterface public immutable priceOracle;

    /// @notice The address of IronBank v1 comptroller
    ComptrollerV1Interface public immutable comptrollerV1;

    enum Error {
        NoError,
        MarketNotListed,
        InsufficientLiquidity,
        SupplyPaused,
        BorrowPaused,
        SupplyCapReached,
        BorrowCapReached
    }

    struct UserV1Supply {
        uint256 ibTokenV1Amount;
        uint256 v1ExchangeRate;
        uint256 v1SupplyAmount;
        bool isCollateral;
        Error migratable;
    }

    struct UserV1Borrow {
        uint256 v1BorrowAmount;
        Error migratable;
    }

    struct MigrationData {
        address market;
        address ibTokenV1;
        uint256 marketPrice;
        UserV1Supply userV1Supply;
        UserV1Borrow userV1Borrow;
        uint256 v1CollateralFactor;
        uint16 v2CollateralFactor;
    }

    /**
     * @notice Construct a new MigrationExtensionLens contract
     * @param ironBank_ The IronBank v2 contract
     * @param comptrollerV1_ The IronBank v1 comptroller contract
     */
    constructor(address ironBank_, address comptrollerV1_) {
        ironBank = IronBankInterfaceForMigration(ironBank_);
        priceOracle = PriceOracleInterface(ironBank.priceOracle());
        comptrollerV1 = ComptrollerV1Interface(comptrollerV1_);
    }

    /**
     * @notice Check if a user can migrate from v1 to v2 for a list of markets
     * @dev This function is used for off-chain calculation. It only accrues interest for v1 markets.
     * @param user The user to check
     * @param ibTokenV1s The list of v1 markets to check
     * @return The migration data for each market
     */
    function checkUserMigration(address user, address[] memory ibTokenV1s) public returns (MigrationData[] memory) {
        MigrationData[] memory migrationData = new MigrationData[](ibTokenV1s.length);

        for (uint256 i = 0; i < ibTokenV1s.length;) {
            address ibTokenV1 = ibTokenV1s[i];
            require(ComptrollerV1Interface(comptrollerV1).isMarketListed(ibTokenV1), "market not listed in v1");

            // We accrue interest in v1 first before getting user borrow balance and the exchange rate.
            IBTokenV1Interface(ibTokenV1).accrueInterest();

            address market = IBTokenV1Interface(ibTokenV1).underlying();

            // Both v1 and v2 normalize the market price in the same way.
            uint256 marketPrice = priceOracle.getPrice(market);

            DataTypes.MarketConfig memory config = ironBank.getMarketConfiguration(market);
            UserV1Borrow memory userV1Borrow = checkBorrowMarketMigratable(user, ibTokenV1, market, config);

            // If the borrow balance is migrated, the total cash in v1 will increase by the borrow amount.
            uint256 v1CashIncreaseAmount = userV1Borrow.migratable == Error.NoError ? userV1Borrow.v1BorrowAmount : 0;
            UserV1Supply memory userV1Supply =
                checkSupplyMarketMigratable(user, ibTokenV1, market, config, v1CashIncreaseAmount);

            // Get both v1 and v2 collateral factors.
            (, uint256 v1CollateralFactor,) = comptrollerV1.markets(ibTokenV1);
            uint16 v2CollateralFactor = config.collateralFactor;

            migrationData[i] = MigrationData({
                market: market,
                ibTokenV1: ibTokenV1,
                marketPrice: marketPrice,
                userV1Supply: userV1Supply,
                userV1Borrow: userV1Borrow,
                v1CollateralFactor: v1CollateralFactor,
                v2CollateralFactor: v2CollateralFactor
            });

            unchecked {
                i++;
            }
        }

        return migrationData;
    }

    /**
     * @dev Check if a user can migrate from v1 to v2 for a borrow market
     * @param user The user to check
     * @param ibTokenV1 The v1 market to check
     * @param market The underlying market
     * @param config The market configuration in v2
     * @return The user v1 borrow data
     */
    function checkBorrowMarketMigratable(
        address user,
        address ibTokenV1,
        address market,
        DataTypes.MarketConfig memory config
    ) internal view returns (UserV1Borrow memory) {
        // Check if the market is listed in v2.
        if (!ironBank.isMarketListed(market)) {
            return UserV1Borrow({v1BorrowAmount: 0, migratable: Error.MarketNotListed});
        }

        // We accrued interest before.
        uint256 borrowAmount = IBTokenV1Interface(ibTokenV1).borrowBalanceStored(user);

        // Check if the borrow amount is 0.
        if (borrowAmount == 0) {
            return UserV1Borrow({v1BorrowAmount: 0, migratable: Error.NoError});
        }

        // Check if borrow is paused in v2.
        if (config.isBorrowPaused()) {
            return UserV1Borrow({v1BorrowAmount: borrowAmount, migratable: Error.BorrowPaused});
        }

        uint256 v2TotalCash = ironBank.getTotalCash(market);
        uint256 v2TotalBorrow = ironBank.getTotalBorrow(market);

        // Check if the market in v2 has enough liquidity to borrow.
        if (borrowAmount > v2TotalCash) {
            return UserV1Borrow({v1BorrowAmount: borrowAmount, migratable: Error.InsufficientLiquidity});
        }

        // Check if the borrow cap will be reached in v2.
        if (config.borrowCap != 0 && v2TotalBorrow + borrowAmount > config.borrowCap) {
            return UserV1Borrow({v1BorrowAmount: borrowAmount, migratable: Error.BorrowCapReached});
        }

        return UserV1Borrow({v1BorrowAmount: borrowAmount, migratable: Error.NoError});
    }

    /**
     * @dev Check if a user can migrate from v1 to v2 for a supply market
     * @param user The user to check
     * @param ibTokenV1 The v1 market to check
     * @param market The underlying market
     * @param config The market configuration in v2
     * @param v1CashIncreaseAmount The amount of cash in v1 that will increase
     * @return The user v1 supply data
     */
    function checkSupplyMarketMigratable(
        address user,
        address ibTokenV1,
        address market,
        DataTypes.MarketConfig memory config,
        uint256 v1CashIncreaseAmount
    ) internal view returns (UserV1Supply memory) {
        // Check if the market is listed in v2.
        if (!ironBank.isMarketListed(market)) {
            return UserV1Supply({
                ibTokenV1Amount: 0,
                v1ExchangeRate: 0,
                v1SupplyAmount: 0,
                isCollateral: false,
                migratable: Error.MarketNotListed
            });
        }

        // We accrued interest before.
        uint256 v1ExchangeRate = IBTokenV1Interface(ibTokenV1).exchangeRateStored();
        uint256 ibTokenV1Amount = IERC20(ibTokenV1).balanceOf(user);
        uint256 v1SupplyAmount = ibTokenV1Amount * v1ExchangeRate / 1e18;
        uint256 v1TotalCash = IBTokenV1Interface(ibTokenV1).getCash() + v1CashIncreaseAmount;

        if (v1SupplyAmount == 0) {
            return UserV1Supply({
                ibTokenV1Amount: ibTokenV1Amount,
                v1ExchangeRate: v1ExchangeRate,
                v1SupplyAmount: v1SupplyAmount,
                isCollateral: false,
                migratable: Error.NoError
            });
        }

        bool isCollateral = ComptrollerV1Interface(comptrollerV1).checkMembership(user, ibTokenV1);

        // Check if the market in v1 has enough liquidity to redeem.
        if (v1SupplyAmount > v1TotalCash) {
            return UserV1Supply({
                ibTokenV1Amount: ibTokenV1Amount,
                v1ExchangeRate: v1ExchangeRate,
                v1SupplyAmount: v1SupplyAmount,
                isCollateral: isCollateral,
                migratable: Error.InsufficientLiquidity
            });
        }

        // Check if supply is paused in v2.
        if (config.isSupplyPaused()) {
            return UserV1Supply({
                ibTokenV1Amount: ibTokenV1Amount,
                v1ExchangeRate: v1ExchangeRate,
                v1SupplyAmount: v1SupplyAmount,
                isCollateral: isCollateral,
                migratable: Error.SupplyPaused
            });
        }

        uint256 v2TotalSupply = ironBank.getTotalSupply(market);
        uint256 v2ExchangeRate = ironBank.getExchangeRate(market);
        uint256 v2TotalSupplyUnderlying = v2TotalSupply * 1e18 / v2ExchangeRate;

        // Check if the supply cap will be reached in v2.
        if (config.supplyCap != 0 && v2TotalSupplyUnderlying + v1SupplyAmount > config.supplyCap) {
            return UserV1Supply({
                ibTokenV1Amount: ibTokenV1Amount,
                v1ExchangeRate: v1ExchangeRate,
                v1SupplyAmount: v1SupplyAmount,
                isCollateral: isCollateral,
                migratable: Error.SupplyCapReached
            });
        }

        return UserV1Supply({
            ibTokenV1Amount: ibTokenV1Amount,
            v1ExchangeRate: v1ExchangeRate,
            v1SupplyAmount: v1SupplyAmount,
            isCollateral: isCollateral,
            migratable: Error.NoError
        });
    }
}
