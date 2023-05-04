// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../Common.t.sol";
import "../../src/libraries/DataTypes.sol";
import "../../src/libraries/PauseFlags.sol";

contract ArraysTest is Test, Common {
    using PauseFlags for DataTypes.MarketConfig;

    function testSupplyPaused() public {
        DataTypes.MarketConfig memory config;

        config.setSupplyPaused(true);
        assertTrue(config.isSupplyPaused());

        config.setSupplyPaused(true); // nothing changes
        assertTrue(config.isSupplyPaused());

        config.setSupplyPaused(false);
        assertFalse(config.isSupplyPaused());

        config.setSupplyPaused(false); // nothing changes
        assertFalse(config.isSupplyPaused());
    }

    function testBorrowPaused() public {
        DataTypes.MarketConfig memory config;

        config.setBorrowPaused(true);
        assertTrue(config.isBorrowPaused());

        config.setBorrowPaused(true); // nothing changes
        assertTrue(config.isBorrowPaused());

        config.setBorrowPaused(false);
        assertFalse(config.isBorrowPaused());

        config.setBorrowPaused(false); // nothing changes
        assertFalse(config.isBorrowPaused());
    }

    function testTransferPaused() public {
        DataTypes.MarketConfig memory config;

        config.setTransferPaused(true);
        assertTrue(config.isTransferPaused());

        config.setTransferPaused(true); // nothing changes
        assertTrue(config.isTransferPaused());

        config.setTransferPaused(false);
        assertFalse(config.isTransferPaused());

        config.setTransferPaused(false); // nothing changes
        assertFalse(config.isTransferPaused());
    }
}
