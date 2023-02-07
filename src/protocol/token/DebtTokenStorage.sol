// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract DebtTokenStorage {
    event DebtApproval(address indexed from, address indexed to, uint256 indexed amount);

    event TransferDebt(address indexed from, address indexed to, uint256 indexed value);

    address internal _pool;

    address internal _underlying;

    mapping(address => mapping(address => uint256)) internal _debtAllowances;
}
