// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "./IBTokenStorage.sol";
import "../../interfaces/IBTokenInterface.sol";
import "../../interfaces/IronBankInterface.sol";

contract IBToken is
    Initializable,
    ERC20Upgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    IBTokenStorage,
    IBTokenInterface
{
    /**
     * @notice Initialize the contract
     */
    function initialize(string memory name_, string memory symbol_, address admin_, address ironBank_, address market_)
        public
        initializer
    {
        __ERC20_init(name_, symbol_);
        __Ownable_init();
        __UUPSUpgradeable_init();

        transferOwnership(admin_);
        ironBank = ironBank_;
        market = market_;
    }

    /**
     * @notice Check if the caller is Iron Bank.
     */
    modifier onlyIronBank() {
        _checkIronBank();
        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Return the underlying market.
     */
    function asset() public view returns (address) {
        return market;
    }

    /// @inheritdoc ERC20Upgradeable
    function totalSupply() public view virtual override returns (uint256) {
        return IronBankInterface(ironBank).getTotalSupply(market);
    }

    /// @inheritdoc ERC20Upgradeable
    function balanceOf(address account) public view override returns (uint256) {
        return IronBankInterface(ironBank).getIBTokenBalance(account, market);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Transfer IBToken to another address.
     * @param to The address to receive IBToken
     * @param amount The amount of IBToken to transfer
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        IronBankInterface(ironBank).transferIBToken(market, msg.sender, to, amount);
        return super.transfer(to, amount);
    }

    /**
     * @notice Transfer IBToken from one address to another.
     * @param from The address to send IBToken from
     * @param to The address to receive IBToken
     * @param amount The amount of IBToken to transfer
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        IronBankInterface(ironBank).transferIBToken(market, from, to, amount);
        return super.transferFrom(from, to, amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice Mint IBToken.
     * @dev This function will only emit a Transfer event.
     * @param account The address to receive IBToken
     * @param amount The amount of IBToken to mint
     */
    function mint(address account, uint256 amount) external onlyIronBank {
        emit Transfer(address(0), account, amount);
    }

    /**
     * @notice Burn IBToken.
     * @dev This function will only emit a Transfer event.
     * @param account The address to burn IBToken from
     * @param amount The amount of IBToken to burn
     */
    function burn(address account, uint256 amount) external onlyIronBank {
        emit Transfer(account, address(0), amount);
    }

    /**
     * @notice Seize IBToken.
     * @dev This function will only be called when a liquidation occurs.
     * @param from The address to seize IBToken from
     * @param to The address to receive IBToken
     * @param amount The amount of IBToken to seize
     */
    function seize(address from, address to, uint256 amount) external onlyIronBank {
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

    /**
     * @dev Check if the caller is the Iron Bank.
     */
    function _checkIronBank() internal view {
        require(msg.sender == ironBank, "!authorized");
    }

    /// @inheritdoc ERC20Upgradeable
    function _transfer(address from, address to, uint256 amount) internal override {
        emit Transfer(from, to, amount);
    }
}
