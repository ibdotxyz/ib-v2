// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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
     * @notice Given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
     * @param amountOut The amount of the asset to convert
     * @param reserveIn The reserve of the first asset
     * @param reserveOut The reserve of the second asset
     */
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
