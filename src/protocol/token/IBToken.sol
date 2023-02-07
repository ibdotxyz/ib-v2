// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "./IBTokenStorage.sol";
import "../../interfaces/IronBankInterface.sol";

contract IBToken is Initializable, ERC20Upgradeable, UUPSUpgradeable, OwnableUpgradeable, IBTokenStorage {
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

    modifier onlyPool() {
        _checkPool();
        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function getPool() public view returns (address) {
        return _pool;
    }

    function getUnderlying() public view returns (address) {
        return _underlying;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function transfer(address to, uint256 amount) public override returns (bool) {
        IronBankInterface(getPool()).transferIBToken(getUnderlying(), msg.sender, to, amount);
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        IronBankInterface(getPool()).transferIBToken(getUnderlying(), from, to, amount);
        return super.transferFrom(from, to, amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function mint(address account, uint256 amount) external onlyPool {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external onlyPool {
        _burn(account, amount);
    }

    function seize(address from, address to, uint256 amount) external onlyPool {
        require(from != to, "cannot self seize");
        _transfer(from, to, amount);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev _authorizeUpgrade is used by UUPSUpgradeable to determine if it's allowed to upgrade a proxy implementation.
     * @param newImplementation The new implementation
     *
     * Ref: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/utils/UUPSUpgradeable.sol
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _checkPool() internal view {
        require(msg.sender == getPool(), "!pool");
    }
}
