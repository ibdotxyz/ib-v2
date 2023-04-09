// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "v2-core/interfaces/IUniswapV2Pair.sol";

library UniswapV2Utils {
    /**
     * @notice Compute the CREATE2 address for a pair without making any external calls
     * @param factory The Uniswap V2 factory contract address
     * @param tokenA The first token
     * @param tokenB The second token
     */
    function computeAddress(address factory, address tokenA, address tokenB) internal pure returns (address pool) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(token0, token1)),
                            hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f" // init code hash
                        )
                    )
                )
            )
        );
    }

    /**
     * @notice Fetches reserves for a pair
     * @param factory The Uniswap V2 factory contract address
     * @param tokenA The first token
     * @param tokenB The second token
     */
    function getReserves(address factory, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(computeAddress(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA < tokenB ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /**
     * @notice Given an output amount of an asset and pair reserves, returns a required input amount of the other asset
     * @param amountOut The output amount of the asset
     * @param reserveIn The reserve of the first asset
     * @param reserveOut The reserve of the second asset
     */
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "insufficient output amount");
        require(reserveIn > 0 && reserveOut > 0, "insufficient liquidity");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    /**
     * @notice Given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
     * @param amountIn The input amount of the asset
     * @param reserveIn The reserve of the first asset
     * @param reserveOut The reserve of the second asset
     */
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "insufficient input amount");
        require(reserveIn > 0 && reserveOut > 0, "insufficient liquidity");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /**
     * @notice Performs chained getAmountIn calculations on any number of pairs
     * @dev The returned array is the reverse of what is returned by official Uniswap v2's library.
     * @param factory The Uniswap V2 factory contract address
     * @param amountOut The output amount of the asset
     * @param path The path of token addresses
     */
    function getAmountsIn(address factory, uint256 amountOut, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "invalid path");
        amounts = new uint256[](path.length);
        amounts[0] = amountOut;
        for (uint256 i = 0; i < path.length - 1;) {
            (uint256 reserveOut, uint256 reserveIn) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountIn(amounts[i], reserveIn, reserveOut);

            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Performs chained getAmountOut calculations on any number of pairs
     * @param factory The Uniswap V2 factory contract address
     * @param amountIn The input amount of the asset
     * @param path The path of token addresses
     */
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "invalid path");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i = 0; i < path.length - 1;) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);

            unchecked {
                i++;
            }
        }
    }
}
