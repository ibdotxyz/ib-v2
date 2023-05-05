// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Constants.sol";
import "./Events.sol";
import "../../libraries/DataTypes.sol";

contract IronBankStorage is Constants, Events {
    mapping(address => DataTypes.Market) public markets;
    address[] public allMarkets;

    mapping(address => mapping(address => bool)) public enteredMarkets;
    mapping(address => address[]) public allEnteredMarkets;
    mapping(address => mapping(address => bool)) public allowedExtensions;
    mapping(address => address[]) public allAllowedExtensions;
    mapping(address => mapping(address => uint256)) public creditLimits;
    mapping(address => address[]) public allCreditMarkets;
    mapping(address => uint8) public liquidityCheckStatus;

    address public priceOracle;

    address public marketConfigurator;
    address public creditLimitManager;
    address public reserveManager;
}
