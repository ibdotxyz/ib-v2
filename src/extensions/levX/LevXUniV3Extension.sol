// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "v3-core/interfaces/IUniswapV3Factory.sol";
import "v3-core/interfaces/IUniswapV3Pool.sol";
import "v3-core/libraries/SafeCast.sol";
import "v3-core/libraries/TickMath.sol";
import "v3-periphery/libraries/Path.sol";
import "../../interfaces/IronBankInterface.sol";

import "forge-std/Test.sol";

contract LevXUniV3Extension is Ownable2Step, Test {
    using Path for bytes;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    IronBankInterface public immutable ironBank;
    IUniswapV3Factory public immutable factory;
    address public immutable weth;

    mapping(address => bool) public isAllowed;

    event AssetAllowedSet(address asset, bool allowed);

    event Seized(address asset, uint256 amount);

    constructor(address ironBank_, address factory_, address weth_) {
        ironBank = IronBankInterface(ironBank_);
        factory = IUniswapV3Factory(factory_);
        weth = weth_;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function isAssetSupport(address asset) public view returns (bool) {
        return ironBank.isMarketListed(asset) && isAllowed[asset];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    struct CollateralData {
        address asset;
        uint256 amount;
    }

    function addCollateral(CollateralData[] memory collateralData) public {
        for (uint256 i = 0; i < collateralData.length;) {
            IERC20(collateralData[i].asset).safeTransferFrom(msg.sender, address(this), collateralData[i].amount);
            IERC20(collateralData[i].asset).safeIncreaseAllowance(address(ironBank), collateralData[i].amount);
            ironBank.supply(msg.sender, collateralData[i].asset, collateralData[i].amount);
            ironBank.enterMarket(msg.sender, collateralData[i].asset);

            unchecked {
                i++;
            }
        }
    }

    struct SwapData {
        address caller;
        address longAsset;
        uint256 longAmount;
        address shortAsset;
        uint256 maxShortAmount;
        bytes path;
        bool isOpenPosition;
    }

    function open(
        address longAsset,
        uint256 longAmount,
        address shortAsset,
        uint256 maxShortAmount,
        bytes memory path,
        CollateralData[] memory collateralData
    ) public {
        require(longAsset != shortAsset, "invalid long or short asset");
        require(isAssetSupport(longAsset) && isAssetSupport(shortAsset), "long or short asset not support");
        require(longAmount > 0, "invalid long amount");

        // Add collateral for user if provided.
        if (collateralData.length > 0) {
            addCollateral(collateralData);
        }

        exactOutputInternal(
            longAmount,
            address(this),
            SwapData({
                caller: msg.sender,
                longAsset: longAsset,
                longAmount: longAmount,
                shortAsset: shortAsset,
                maxShortAmount: maxShortAmount,
                path: path,
                isOpenPosition: true
            })
        );
    }

    function close(address longAsset, uint256 longAmount, address shortAsset, uint256 maxShortAmount, bytes memory path)
        public
    {
        require(longAsset != shortAsset, "invalid long or short asset");
        require(isAssetSupport(longAsset) && isAssetSupport(shortAsset), "long or short asset not support");

        if (longAmount == type(uint256).max) {
            ironBank.accrueInterest(longAsset);
            longAmount = ironBank.getBorrowBalance(msg.sender, longAsset);
        }
        require(longAmount > 0, "invalid long amount");

        exactOutputInternal(
            longAmount,
            address(this),
            SwapData({
                caller: msg.sender,
                longAsset: longAsset,
                longAmount: longAmount,
                shortAsset: shortAsset,
                maxShortAmount: maxShortAmount,
                path: path,
                isOpenPosition: false
            })
        );
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external {
        require(amount0Delta > 0 || amount1Delta > 0, "invalid amount");
        SwapData memory data = abi.decode(_data, (SwapData));
        (address tokenOut, address tokenIn, uint24 fee) = data.path.decodeFirstPool();
        IUniswapV3Pool pool = getPool(tokenIn, tokenOut, fee);
        require(address(pool) == msg.sender, "invalid pool");

        if (tokenOut == data.longAsset) {
            IERC20(data.longAsset).safeIncreaseAllowance(address(ironBank), data.longAmount);
            if (data.isOpenPosition) {
                ironBank.enterMarket(data.caller, data.longAsset);
                ironBank.supply(data.caller, data.longAsset, data.longAmount);
            } else {
                ironBank.repay(data.caller, data.longAsset, data.longAmount);
            }
        }

        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);

        // Initiate the next swap or repay.
        if (data.path.hasMultiplePools()) {
            data.path = data.path.skipToken();
            exactOutputInternal(amountToPay, address(pool), data);
        } else {
            require(tokenIn == data.shortAsset, "mismatch short asset");
            require(amountToPay <= data.maxShortAmount, "short amount exceed max amount");

            if (data.isOpenPosition) {
                ironBank.borrow(data.caller, data.shortAsset, amountToPay);
            } else {
                ironBank.redeem(data.caller, data.shortAsset, amountToPay);
            }

            // Repay to Uniswap v3 pool.
            IERC20(tokenIn).safeTransfer(address(pool), amountToPay);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    struct AssetAllowed {
        address asset;
        bool allowed;
    }

    function setAssetAllowed(AssetAllowed[] memory assetAllowed) external onlyOwner {
        for (uint256 i = 0; i < assetAllowed.length;) {
            address asset = assetAllowed[i].asset;
            bool allowed = assetAllowed[i].allowed;
            if (isAllowed[asset] != allowed) {
                isAllowed[asset] = allowed;

                emit AssetAllowedSet(asset, allowed);
            }

            unchecked {
                i++;
            }
        }
    }

    function seize(address asset) external onlyOwner {
        uint256 balance = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransfer(owner(), balance);

        emit Seized(asset, balance);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function exactOutputInternal(uint256 amountOut, address recipient, SwapData memory data)
        private
        returns (uint256 amountIn)
    {
        (address tokenOut, address tokenIn, uint24 fee) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0, int256 amount1) = getPool(tokenIn, tokenOut, fee).swap(
            recipient,
            zeroForOne,
            -amountOut.toInt256(),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(data)
        );
        return uint256(zeroForOne ? amount0 : amount1);
    }

    function getPool(address tokenA, address tokenB, uint24 fee) private view returns (IUniswapV3Pool) {
        return IUniswapV3Pool(factory.getPool(tokenA, tokenB, fee));
    }
}
