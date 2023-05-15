// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./DataTypes.sol";

library PauseFlags {
    /// @dev Mask for specific actions in the pause flag bit array
    uint8 internal constant PAUSE_SUPPLY_MASK = 0xFE;
    uint8 internal constant PAUSE_BORROW_MASK = 0xFD;
    uint8 internal constant PAUSE_TRANSFER_MASK = 0xFB;

    /// @dev Offsets for specific actions in the pause flag bit array
    uint8 internal constant PAUSE_SUPPLY_OFFSET = 0;
    uint8 internal constant PAUSE_BORROW_OFFSET = 1;
    uint8 internal constant PAUSE_TRANSFER_OFFSET = 2;

    /// @dev Sets the market supply paused.
    function setSupplyPaused(DataTypes.MarketConfig memory self, bool paused) internal pure {
        self.pauseFlags = (self.pauseFlags & PAUSE_SUPPLY_MASK) | (toUInt8(paused) << PAUSE_SUPPLY_OFFSET);
    }

    /// @dev Returns true if the market supply is paused, and false otherwise.
    function isSupplyPaused(DataTypes.MarketConfig memory self) internal pure returns (bool) {
        return toBool(self.pauseFlags & ~PAUSE_SUPPLY_MASK);
    }

    /// @dev Sets the market borrow paused.
    function setBorrowPaused(DataTypes.MarketConfig memory self, bool paused) internal pure {
        self.pauseFlags = (self.pauseFlags & PAUSE_BORROW_MASK) | (toUInt8(paused) << PAUSE_BORROW_OFFSET);
    }

    /// @dev Returns true if the market borrow is paused, and false otherwise.
    function isBorrowPaused(DataTypes.MarketConfig memory self) internal pure returns (bool) {
        return toBool(self.pauseFlags & ~PAUSE_BORROW_MASK);
    }

    /// @dev Sets the market transfer paused.
    function setTransferPaused(DataTypes.MarketConfig memory self, bool paused) internal pure {
        self.pauseFlags = (self.pauseFlags & PAUSE_TRANSFER_MASK) | (toUInt8(paused) << PAUSE_TRANSFER_OFFSET);
    }

    /// @dev Returns true if the market transfer is paused, and false otherwise.
    function isTransferPaused(DataTypes.MarketConfig memory self) internal pure returns (bool) {
        return toBool(self.pauseFlags & ~PAUSE_TRANSFER_MASK);
    }

    /// @dev Casts a boolean to uint8.
    function toUInt8(bool x) internal pure returns (uint8) {
        return x ? 1 : 0;
    }

    /// @dev Casts a uint8 to boolean.
    function toBool(uint8 x) internal pure returns (bool) {
        return x != 0;
    }
}
