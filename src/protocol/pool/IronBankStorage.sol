// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Constants.sol";

contract IronBankStorage is Constants {
    event MarketListed(address market);

    event MarketDelisted(address market);

    event MarketConfigurationSet(address market, MarketConfig config);

    event MarketConfiguratorSet(address configurator);

    event CreditLimitManagerSet(address manager);

    event ExtensionrRegistrySet(address registry);

    event CreditLimitChanged(address user, address market, uint256 credit);

    event PriceOracleSet(address priceOracle);

    event InterestAccrued(address indexed market, uint256 interestIncreased, uint256 borrowIndex, uint256 totalBorrow);

    event MarketEntered(address indexed market, address indexed user);

    event MarketExited(address indexed market, address indexed user);

    event Supply(address indexed market, address indexed user, uint256 indexed amount, uint256 ibTokenAmount);

    event Borrow(
        address indexed market, address indexed user, uint256 indexed amount, uint256 accountBorrow, uint256 totalBorrow
    );

    event Redeem(address indexed market, address indexed user, uint256 indexed amount, uint256 ibTokenAmount);

    event Repay(
        address indexed market, address indexed user, uint256 indexed amount, uint256 accountBorrow, uint256 totalBorrow
    );

    event Liquidate(
        address liquidator, address violator, address marketBorrow, address marketCollateral, uint256 repayAmount
    );

    event UserCollateralChanged(address indexed market, address indexed user, uint256 indexed amount);

    event TokenSeized(address token, address recipient, uint256 amount);

    event ReservesIncreased(address market, uint256 ibTokenAmount, uint256 amount);

    event ReservesDecreased(address market, uint256 ibTokenAmount, uint256 amount, address recipient);

    struct UserBorrow {
        uint256 borrowBalance;
        uint256 borrowIndex;
    }

    struct MarketConfig {
        // TODO
        // 1 + 2 + 2 + 2 + 2 + 1 + 1 + 1
        bool isListed;
        uint16 collateralFactor;
        uint16 liquidationThreshold;
        uint16 liquidationBonus;
        uint16 reserveFactor;
        bool supplyPaused;
        bool borrowPaused;
        bool isFrozen;
        // 20 + 20 + 20 + 32 + 32 + 32 + 32
        address ibTokenAddress;
        address debtTokenAddress;
        address interestRateModelAddress;
        uint256 supplyCap;
        uint256 collateralCap;
        uint256 borrowCap;
        uint256 initialExchangeRate;
    }

    struct Market {
        MarketConfig config;
        uint40 lastUpdateTimestamp;
        uint256 totalCash;
        uint256 totalBorrow;
        uint256 totalSupply;
        uint256 totalCollateral;
        uint256 totalReserves;
        uint256 borrowIndex;
        mapping(address => UserBorrow) userBorrows;
        mapping(address => uint256) userCollaterals;
    }

    mapping(address => Market) public markets;
    address[] public allMarkets;

    mapping(address => mapping(address => bool)) public enteredMarkets;
    mapping(address => address[]) public allEnteredMarkets;
    mapping(address => mapping(address => uint256)) public creditLimits;
    mapping(address => address[]) public allCreditMarkets;
    mapping(address => uint8) public liquidityCheckStatus;

    address public priceOracle;

    address public marketConfigurator;
    address public creditLimitManager;
    address public extensionRegistry;
}
