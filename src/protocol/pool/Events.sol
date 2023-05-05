// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../libraries/DataTypes.sol";

abstract contract Events {
    event MarketConfiguratorSet(address configurator);

    event CreditLimitManagerSet(address manager);

    event ReserveManagerSet(address manager);

    event CreditLimitChanged(address indexed user, address indexed market, uint256 credit);

    event PriceOracleSet(address priceOracle);

    event MarketListed(address indexed market, uint40 timestamp, DataTypes.MarketConfig config);

    event MarketDelisted(address indexed market);

    event MarketConfigurationChanged(address indexed market, DataTypes.MarketConfig config);

    event MarketEntered(address indexed market, address indexed user);

    event MarketExited(address indexed market, address indexed user);

    event InterestAccrued(
        address indexed market,
        uint40 timestamp,
        uint256 borrowRatePerSecond,
        uint256 borrowIndex,
        uint256 totalBorrow,
        uint256 totalReserves
    );

    event Supply(
        address indexed market, address indexed from, address indexed to, uint256 amount, uint256 ibTokenAmount
    );

    event Borrow(
        address indexed market,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 accountBorrow,
        uint256 totalBorrow
    );

    event Redeem(
        address indexed market, address indexed from, address indexed to, uint256 amount, uint256 ibTokenAmount
    );

    event Repay(
        address indexed market,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 accountBorrow,
        uint256 totalBorrow
    );

    event Liquidate(
        address indexed liquidator,
        address indexed borrower,
        address indexed marketBorrow,
        address marketCollateral,
        uint256 repayAmount,
        uint256 seizedAmount
    );

    event TokenSeized(address indexed token, address indexed recipient, uint256 amount);

    event ReservesIncreased(address indexed market, uint256 ibTokenAmount, uint256 amount);

    event ReservesDecreased(address indexed market, address indexed recipient, uint256 ibTokenAmount, uint256 amount);

    event ExtensionAdded(address indexed user, address indexed extension);

    event ExtensionRemoved(address indexed user, address indexed extension);
}
