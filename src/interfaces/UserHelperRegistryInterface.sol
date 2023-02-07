// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface UserHelperRegistryInterface {
    function isHelperAuthorized(address user, address helper) external view returns (bool);
}
