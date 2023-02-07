// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface DeferLiquidityCheckInterface {
    function onDeferredLiquidityCheck(bytes memory data) external;
}
