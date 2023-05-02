// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

abstract contract Constants {
    uint256 internal constant INITIAL_BORROW_INDEX = 1e18;
    uint256 internal constant INITIAL_EXCHANGE_RATE = 1e18;
    uint256 internal constant FACTOR_SCALE = 10000;

    uint16 internal constant MAX_COLLATERAL_FACTOR = 9000; // 90%
    uint16 internal constant MAX_LIQUIDATION_THRESHOLD = 10000; // 100%
    uint16 internal constant MIN_LIQUIDATION_BONUS = 10000; // 100%
    uint16 internal constant MAX_LIQUIDATION_BONUS = 12500; // 125%
    uint16 internal constant MAX_LIQUIDATION_THRESHOLD_X_BONUS = 10000; // 100%
    uint16 internal constant MAX_RESERVE_FACTOR = 10000; // 100%

    uint8 internal constant LIQUIDITY_CHECK_NORMAL = 0;
    uint8 internal constant LIQUIDITY_CHECK_DEFERRED = 1;
    uint8 internal constant LIQUIDITY_CHECK_DIRTY = 2;
}
