// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library DataTypes {
    struct UserBorrow {
        uint256 borrowBalance;
        uint256 borrowIndex;
    }

    struct MarketConfig {
        // 1 + 1 + 2 + 2 + 2 + 2 + 1 = 11
        bool isListed;
        uint8 pauseFlags;
        uint16 collateralFactor;
        uint16 liquidationThreshold;
        uint16 liquidationBonus;
        uint16 reserveFactor;
        bool isPToken;
        // 20 + 20 + 20 + 32 + 32 + 32
        address ibTokenAddress;
        address debtTokenAddress;
        address pTokenAddress;
        address interestRateModelAddress;
        uint256 supplyCap;
        uint256 borrowCap;
        uint256 initialExchangeRate;
    }

    struct Market {
        MarketConfig config;
        uint40 lastUpdateTimestamp;
        uint256 totalCash;
        uint256 totalBorrow;
        uint256 totalSupply;
        uint256 totalReserves;
        uint256 borrowIndex;
        mapping(address => UserBorrow) userBorrows;
        mapping(address => uint256) userSupplies;
    }
}
