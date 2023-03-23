// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "uniswap-v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "uniswap-v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../../interfaces/IronBankInterface.sol";

contract LevXExtension is Ownable2Step {
    using SafeERC20 for IERC20;

    IronBankInterface public immutable pool;
    IUniswapV2Factory public immutable factory;
    address public immutable weth;

    mapping(address => bool) public isAllowed;

    event AssetAllowedSet(address asset, bool allowed);

    event Seized(address asset, uint256 amount);

    constructor(address pool_, address factory_, address weth_) {
        pool = IronBankInterface(pool_);
        factory = IUniswapV2Factory(factory_);
        weth = weth_;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function isAssetSupport(address asset) public view returns (bool) {
        return pool.isMarketListed(asset) && isAllowed[asset];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    struct CollateralData {
        address asset;
        uint256 amount;
    }

    function addCollateral(CollateralData[] memory collateralData) public {
        for (uint256 i = 0; i < collateralData.length;) {
            IERC20(collateralData[i].asset).safeTransferFrom(msg.sender, address(this), collateralData[i].amount);
            IERC20(collateralData[i].asset).safeIncreaseAllowance(address(pool), collateralData[i].amount);
            pool.supply(msg.sender, collateralData[i].asset, collateralData[i].amount);
            pool.enterMarket(msg.sender, collateralData[i].asset);

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
        address pairFrom;
        bool isOpenPosition;
    }

    function open(
        address longAsset,
        uint256 longAmount,
        address shortAsset,
        uint256 maxShortAmount,
        CollateralData[] memory collateralData
    ) public {
        require(longAsset != shortAsset, "invalid long or short asset");
        require(isAssetSupport(longAsset) && isAssetSupport(shortAsset), "long or short asset not support");
        if (collateralData.length > 0) {
            addCollateral(collateralData);
        }

        address tokenB = longAsset == weth ? shortAsset : weth;
        (uint256 amount0, uint256 amount1) = longAsset < tokenB ? (longAmount, uint256(0)) : (uint256(0), longAmount);
        address pairFrom = factory.getPair(longAsset, tokenB);
        bytes memory data = abi.encode(
            SwapData({
                caller: msg.sender,
                longAsset: longAsset,
                longAmount: longAmount,
                shortAsset: shortAsset,
                maxShortAmount: maxShortAmount,
                pairFrom: pairFrom,
                isOpenPosition: true
            })
        );

        // Initiate the flash swap.
        IUniswapV2Pair(pairFrom).swap(amount0, amount1, address(this), data);
    }

    function close(address longAsset, uint256 longAmount, address shortAsset, uint256 maxShortAmount) public {
        require(longAsset != shortAsset, "invalid long or short asset");
        require(isAssetSupport(longAsset) && isAssetSupport(shortAsset), "long or short asset not support");

        address tokenB = longAsset == weth ? shortAsset : weth;
        (uint256 amount0, uint256 amount1) = longAsset < tokenB ? (longAmount, uint256(0)) : (uint256(0), longAmount);
        address pairFrom = factory.getPair(longAsset, tokenB);
        bytes memory data = abi.encode(
            SwapData({
                caller: msg.sender,
                longAsset: longAsset,
                longAmount: longAmount,
                shortAsset: shortAsset,
                maxShortAmount: maxShortAmount,
                pairFrom: pairFrom,
                isOpenPosition: true
            })
        );

        // Initiate the flash swap.
        IUniswapV2Pair(pairFrom).swap(amount0, amount1, address(this), data);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        SwapData memory decoded = abi.decode(data, (SwapData));

        require(msg.sender == address(decoded.pairFrom), "not pair");
        require(sender == address(this), "not sender");

        uint256 longAmount = amount0 > 0 ? amount0 : amount1;
        require(longAmount == decoded.longAmount, "incorrect amount");

        IERC20(decoded.longAsset).safeIncreaseAllowance(address(pool), longAmount);
        if (decoded.isOpenPosition) {
            // Supply the long asset for user.
            pool.enterMarket(decoded.caller, decoded.longAsset);
            pool.supply(decoded.caller, decoded.longAsset, longAmount);
        } else {
            // Repay the long asset for user.
            pool.repay(decoded.caller, decoded.longAsset, longAmount);
        }

        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(decoded.pairFrom).getReserves();
        (uint256 reserveIn, uint256 reserveOut) = amount0 > 0 ? (reserve1, reserve0) : (reserve0, reserve1);
        uint256 minRepay = getAmountIn(longAmount, reserveIn, reserveOut);

        if (decoded.longAsset == weth || decoded.shortAsset == weth) {
            // A <-> weth or weth <-> A
            require(minRepay <= decoded.maxShortAmount, "incorrect amount");

            if (decoded.isOpenPosition) {
                // Borrow the short asset for user.
                pool.borrow(decoded.caller, decoded.shortAsset, minRepay);
            } else {
                // Redeem the short asset for user.
                pool.redeem(decoded.caller, decoded.shortAsset, minRepay);
            }

            // Repay the flash swap.
            IERC20(decoded.shortAsset).safeTransfer(address(decoded.pairFrom), minRepay);
        } else {
            // A <-> weth <-> B
            cross(decoded, minRepay);
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

    function cross(SwapData memory decoded, uint256 minWethRepay) internal {
        address pairTo = factory.getPair(decoded.shortAsset, weth);
        address tokenA = decoded.shortAsset < weth ? decoded.shortAsset : weth;

        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pairTo).getReserves();
        (uint256 reserveIn, uint256 reserveOut) =
            tokenA == decoded.shortAsset ? (reserve0, reserve1) : (reserve1, reserve0);
        uint256 minRepay = getAmountIn(minWethRepay, reserveIn, reserveOut);
        require(minRepay <= decoded.maxShortAmount, "incorrect amount");

        if (decoded.isOpenPosition) {
            // Borrow the short asset for user.
            pool.borrow(decoded.caller, decoded.shortAsset, minRepay);
        } else {
            // Redeem the short asset for user.
            pool.redeem(decoded.caller, decoded.shortAsset, minRepay);
        }

        // Repay the flash swap.
        (uint256 amount0, uint256 amount1) =
            tokenA == decoded.shortAsset ? (uint256(0), minWethRepay) : (minWethRepay, uint256(0));
        IERC20(decoded.shortAsset).safeTransfer(pairTo, minRepay);
        IUniswapV2Pair(pairTo).swap(amount0, amount1, decoded.pairFrom, new bytes(0));
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }
}
