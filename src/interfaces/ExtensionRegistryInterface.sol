// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ExtensionRegistryInterface {
    function isAuthorized(address user, address helper) external view returns (bool);
}
