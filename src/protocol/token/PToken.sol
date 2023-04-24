// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/PTokenInterface.sol";

contract PToken is ERC20, Ownable, PTokenInterface {
    using SafeERC20 for IERC20;

    address public immutable underlying;

    constructor(string memory name_, string memory symbol_, address underlying_) ERC20(name_, symbol_) {
        underlying = underlying_;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Return the decimals of the pToken.
     * @return The decimals of the pToken
     */
    function decimals() public view override returns (uint8) {
        return ERC20(underlying).decimals();
    }

    /**
     * @notice Return the underlying asset of the pToken.
     * @return The underlying asset of the pToken
     */
    function getUnderlying() public view returns (address) {
        return underlying;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Wrap the underlying asset to pToken.
     * @param amount The amount of underlying to wrap
     */
    function wrap(uint256 amount) external {
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        absorb(msg.sender);
    }

    /**
     * @notice Unwrap the pToken to the underlying asset.
     * @param amount The amount of pToken to unwrap
     */
    function unwrap(uint256 amount) external {
        _burn(msg.sender, amount);
        IERC20(underlying).safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Absorb the surplus underlying asset to user.
     * @dev This function should only be called by contracts.
     * @param user The beneficiary to absorb the surplus underlying asset
     */
    function absorb(address user) public {
        uint256 balance = IERC20(underlying).balanceOf(address(this));

        uint256 amount = balance - totalSupply();
        _mint(user, amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice Seize the unrelated token to owner.
     * @param asset The asset to seize
     */
    function seize(address asset) external onlyOwner {
        require(asset != underlying, "cannot seize underlying");

        uint256 balance = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransfer(owner(), balance);
    }
}
