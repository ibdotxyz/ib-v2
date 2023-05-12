// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface DeferLiquidityCheckInterface {
    /**
     * @dev The callback function that deferLiquidityCheck will invoke.
     * @param data The arbitrary data that was passed in by the caller
     */
    function onDeferredLiquidityCheck(bytes memory data) external;
}
