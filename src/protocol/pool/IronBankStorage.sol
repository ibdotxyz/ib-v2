// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Constants.sol";
import "./Events.sol";
import "../../libraries/DataTypes.sol";

contract IronBankStorage is Constants, Events {
    /// @notice The mapping of the supported markets
    mapping(address => DataTypes.Market) public markets;

    /// @notice The list of all supported markets
    address[] public allMarkets;

    /// @notice The mapping of a user's entered markets
    mapping(address => mapping(address => bool)) public enteredMarkets;

    /// @notice The list of all markets a user has entered
    mapping(address => address[]) public allEnteredMarkets;

    /// @notice The mapping of a user's allowed extensions
    mapping(address => mapping(address => bool)) public allowedExtensions;

    /// @notice The list of all allowed extensions for a user
    mapping(address => address[]) public allAllowedExtensions;

    /// @notice The mapping of the credit limits
    mapping(address => mapping(address => uint256)) public creditLimits;

    /// @notice The list of a user's credit markets
    mapping(address => address[]) public allCreditMarkets;

    /// @notice The mapping of the liquidity check status
    mapping(address => uint8) public liquidityCheckStatus;

    /// @notice The price oracle address
    address public priceOracle;

    /// @notice The market configurator address
    address public marketConfigurator;

    /// @notice The credit limit manager address
    address public creditLimitManager;

    /// @notice The reserve manager address
    address public reserveManager;
}
