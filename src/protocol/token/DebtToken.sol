// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "./DebtTokenStorage.sol";
import "../../interfaces/IronBankInterface.sol";

contract DebtToken is Initializable, ERC20Upgradeable, UUPSUpgradeable, OwnableUpgradeable, DebtTokenStorage {
    /**
     * @notice Initialize the contract
     */
    function initialize(string memory name_, string memory symbol_, address admin_, address pool_, address underlying_)
        public
        initializer
    {
        __ERC20_init(name_, symbol_);
        __Ownable_init();
        __UUPSUpgradeable_init();

        transferOwnership(admin_);
        _pool = pool_;
        _underlying = underlying_;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function getPool() public view returns (address) {
        return _pool;
    }

    function getUnderlying() public view returns (address) {
        return _underlying;
    }

    function debtAllowance(address from, address to) public view returns (uint256) {
        return _debtAllowances[from][to];
    }

    function balanceOf(address account) public view override returns (uint256) {
        return IronBankInterface(getPool()).getBorrowBalance(account, getUnderlying());
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function approve(address, uint256) public override returns (bool) {
        _pool = _pool; // Shh
        revert("unsupported");
    }

    function increaseAllowance(address, uint256) public override returns (bool) {
        _pool = _pool; // Shh
        revert("unsupported");
    }

    function decreaseAllowance(address, uint256) public override returns (bool) {
        _pool = _pool; // Shh
        revert("unsupported");
    }

    function approveDebt(address debtOwner, uint256 amount) public returns (bool) {
        _approveDebt(debtOwner, msg.sender, amount);
        return true;
    }

    function increaseDebtAllowance(address debtOwner, uint256 addedValue) public returns (bool) {
        _approveDebt(debtOwner, msg.sender, debtAllowance(debtOwner, msg.sender) + addedValue);
        return true;
    }

    function decreaseDebtAllowance(address debtOwner, uint256 subtractedValue) public returns (bool) {
        uint256 currentAllowance = allowance(debtOwner, msg.sender);
        require(currentAllowance >= subtractedValue, "decreased allowance below zero");
        unchecked {
            _approveDebt(debtOwner, msg.sender, currentAllowance - subtractedValue);
        }
        return true;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        return transferFrom(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _spendDebtAllowance(from, to, amount);
        IronBankInterface(getPool()).transferDebt(getUnderlying(), from, to, amount);

        emit TransferDebt(from, to, amount);
        return true;
    }

    function receiveDebt(address from, uint256 amount) public returns (bool) {
        IronBankInterface(getPool()).transferDebt(getUnderlying(), from, msg.sender, amount);

        emit TransferDebt(from, msg.sender, amount);
        return true;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev _authorizeUpgrade is used by UUPSUpgradeable to determine if it's allowed to upgrade a proxy implementation.
     * @param newImplementation The new implementation
     *
     * Ref: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/utils/UUPSUpgradeable.sol
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _approveDebt(address from, address to, uint256 amount) internal {
        require(from != address(0), "cannot approve debt from zero address");
        require(to != address(0), "cannot approve debt to zero address");

        _debtAllowances[from][to] = amount;
        emit DebtApproval(from, to, amount);
    }

    function _spendDebtAllowance(address from, address to, uint256 amount) internal {
        uint256 currentDebtAllowance = debtAllowance(from, to);
        if (currentDebtAllowance != type(uint256).max) {
            require(currentDebtAllowance >= amount, "insufficient debt allowance");
            unchecked {
                _approveDebt(from, to, currentDebtAllowance - amount);
            }
        }
    }
}
