// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./DebtTokenStorage.sol";
import "../../interfaces/DebtTokenInterface.sol";
import "../../interfaces/IronBankInterface.sol";

contract DebtToken is Initializable, UUPSUpgradeable, OwnableUpgradeable, DebtTokenStorage, DebtTokenInterface {
    /**
     * @notice Initialize the contract
     */
    function initialize(string memory name_, string memory symbol_, address admin_, address ironBank_, address market_)
        public
        initializer
    {
        __Ownable_init();
        __UUPSUpgradeable_init();

        transferOwnership(admin_);
        _name = name_;
        _symbol = symbol_;
        ironBank = ironBank_;
        market = market_;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Return the underlying market.
     */
    function asset() public view returns (address) {
        return market;
    }

    /// @inheritdoc IERC20Metadata
    function name() public view returns (string memory) {
        return _name;
    }

    /// @inheritdoc IERC20Metadata
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /// @inheritdoc IERC20Metadata
    function decimals() public view returns (uint8) {
        return IERC20Metadata(market).decimals();
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view returns (uint256) {
        return IronBankInterface(ironBank).getBorrowBalance(account, market);
    }

    /// @inheritdoc IERC20
    function totalSupply() public view returns (uint256) {
        return IronBankInterface(ironBank).getTotalBorrow(market);
    }

    /// @inheritdoc IERC20
    function allowance(address, address) public view returns (uint256) {
        ironBank; // Shh
        revert("unsupported");
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @dev Comply the standard ERC20 interface but disable the functionality.
    function approve(address, uint256) public returns (bool) {
        ironBank = ironBank; // Shh
        revert("unsupported");
    }

    /// @dev Comply the standard ERC20 interface but disable the functionality.
    function increaseAllowance(address, uint256) public returns (bool) {
        ironBank = ironBank; // Shh
        revert("unsupported");
    }

    /// @dev Comply the standard ERC20 interface but disable the functionality.
    function decreaseAllowance(address, uint256) public returns (bool) {
        ironBank = ironBank; // Shh
        revert("unsupported");
    }

    /// @dev Comply the standard ERC20 interface but disable the functionality.
    function transfer(address, uint256) public returns (bool) {
        ironBank = ironBank; // Shh
        revert("unsupported");
    }

    /// @dev Comply the standard ERC20 interface but disable the functionality.
    function transferFrom(address, address, uint256) public returns (bool) {
        ironBank = ironBank; // Shh
        revert("unsupported");
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev _authorizeUpgrade is used by UUPSUpgradeable to determine if it's allowed to upgrade a proxy implementation.
     * @param newImplementation The new implementation
     *
     * Ref: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/utils/UUPSUpgradeable.sol
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
