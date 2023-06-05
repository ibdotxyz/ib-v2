// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "openzeppelin-contracts/contracts/security/Pausable.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/DeferLiquidityCheckInterface.sol";
import "../interfaces/IronBankInterface.sol";
import "./interfaces/ComptrollerV1Interface.sol";
import "./interfaces/IBTokenV1Interface.sol";
import "./interfaces/WethInterface.sol";

contract MigrationExtension is Pausable, ReentrancyGuard, Ownable2Step, DeferLiquidityCheckInterface {
    using SafeERC20 for IERC20;

    /// @notice The address representing ETH
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice The address of IronBank v2
    IronBankInterface public immutable ironBank;

    /// @notice The address of IronBank v1 comptroller
    ComptrollerV1Interface public immutable comptrollerV1;

    /// @notice The address of WETH
    address public immutable weth;

    struct AdditionalSupply {
        address market;
        uint256 amount;
    }

    /**
     * @notice Construct a new MigrationExtensionLens contract
     * @param ironBank_ The IronBank v2 contract
     * @param comptrollerV1_ The IronBank v1 comptroller contract
     * @param weth_ The WETH contract
     */
    constructor(address ironBank_, address comptrollerV1_, address weth_) {
        ironBank = IronBankInterface(ironBank_);
        comptrollerV1 = ComptrollerV1Interface(comptrollerV1_);
        weth = weth_;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Migrate assets from IronBank v1 to IronBank v2.
     * @param v1SupplyMarkets The user supply markets in v1
     * @param v1BorrowMarkets The user borrow markets in v1
     * @param additionalSupply The additional supply data to v2
     */
    function migrate(
        address[] memory v1SupplyMarkets,
        address[] memory v1BorrowMarkets,
        AdditionalSupply[] memory additionalSupply
    ) external payable nonReentrant whenNotPaused {
        bytes memory data = abi.encode(msg.sender, v1SupplyMarkets, v1BorrowMarkets, additionalSupply);
        ironBank.deferLiquidityCheck(msg.sender, data);
    }

    /// @inheritdoc DeferLiquidityCheckInterface
    function onDeferredLiquidityCheck(bytes memory encodedData) external payable override {
        require(msg.sender == address(ironBank), "untrusted message sender");

        (
            address initiator,
            address[] memory v1SupplyMarkets,
            address[] memory v1BorrowMarkets,
            AdditionalSupply[] memory additionalSupply
        ) = abi.decode(encodedData, (address, address[], address[], AdditionalSupply[]));

        // Borrow from v2 to repay for v1.
        for (uint256 i = 0; i < v1BorrowMarkets.length;) {
            address ibTokenV1 = v1BorrowMarkets[i];
            require(ComptrollerV1Interface(comptrollerV1).isMarketListed(ibTokenV1), "market not listed in v1");

            address underlying = IBTokenV1Interface(ibTokenV1).underlying();

            // Borrow from v2.
            uint256 borrowAmount = IBTokenV1Interface(ibTokenV1).borrowBalanceCurrent(initiator);
            ironBank.borrow(initiator, address(this), underlying, borrowAmount);

            // Approve v1 and repay.
            IERC20(underlying).safeIncreaseAllowance(ibTokenV1, borrowAmount);
            IBTokenV1Interface(ibTokenV1).repayBorrowBehalf(initiator, borrowAmount);

            unchecked {
                i++;
            }
        }

        // Redeem v1 tokens and supply to v2.
        for (uint256 i = 0; i < v1SupplyMarkets.length;) {
            address ibTokenV1 = v1SupplyMarkets[i];
            require(ComptrollerV1Interface(comptrollerV1).isMarketListed(ibTokenV1), "market not listed in v1");

            address underlying = IBTokenV1Interface(ibTokenV1).underlying();

            // Transfer v1 token from initiator and redeem.
            uint256 redeemAmount = IERC20(ibTokenV1).balanceOf(initiator);
            IERC20(ibTokenV1).transferFrom(initiator, address(this), redeemAmount);
            IBTokenV1Interface(ibTokenV1).redeem(redeemAmount);

            // Approve v2 and supply.
            uint256 balance = IERC20(underlying).balanceOf(address(this));
            IERC20(underlying).safeIncreaseAllowance(address(ironBank), balance);
            ironBank.supply(address(this), initiator, underlying, balance);

            unchecked {
                i++;
            }
        }

        // Supply additional collateral if provided.
        for (uint256 i = 0; i < additionalSupply.length;) {
            if (additionalSupply[i].market == ETH) {
                WethInterface(weth).deposit{value: msg.value}();
                IERC20(weth).safeIncreaseAllowance(address(ironBank), msg.value);
                ironBank.supply(address(this), initiator, weth, msg.value);
            } else {
                ironBank.supply(initiator, initiator, additionalSupply[i].market, additionalSupply[i].amount);
            }

            unchecked {
                i++;
            }
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice Admin pauses the contract.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Admin unpauses the contract.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Admin seizes the asset from the contract.
     * @param recipient The recipient of the seized asset.
     * @param asset The asset to seize.
     */
    function seize(address recipient, address asset) external onlyOwner {
        IERC20(asset).safeTransfer(recipient, IERC20(asset).balanceOf(address(this)));
    }
}
