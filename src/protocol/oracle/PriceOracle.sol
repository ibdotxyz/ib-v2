// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import "chainlink/contracts/src/v0.8/Denominations.sol";
import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../extensions/interfaces/WstEthInterface.sol";
import "../../interfaces/PriceOracleInterface.sol";

contract PriceOracle is Ownable2Step, PriceOracleInterface {
    /// @notice The Chainlink feed registry
    FeedRegistryInterface public immutable registry;

    /// @notice The address of Lido staked ETH
    address public immutable steth;

    /// @notice The address of Lido wrapped staked ETH
    address public immutable wsteth;

    struct AggregatorInfo {
        address base;
        address quote;
    }

    /// @notice The mapping from asset to aggregator
    mapping(address => AggregatorInfo) public aggregators;

    constructor(address registry_, address steth_, address wsteth_) {
        registry = FeedRegistryInterface(registry_);
        steth = steth_;
        wsteth = wsteth_;
    }

    /**
     * @notice Get the price of an asset in USD.
     * @dev The price returned will be normalized by asset's decimals.
     * @param asset The asset to get the price of
     * @return The price of the asset in USD
     */
    function getPrice(address asset) external view returns (uint256) {
        if (asset == wsteth) {
            uint256 stEthPrice = getPriceFromChainlink(steth, Denominations.USD);
            uint256 stEthPerToken = WstEthInterface(wsteth).stEthPerToken();
            uint256 wstEthPrice = (stEthPrice * stEthPerToken) / 1e18;
            return getNormalizedPrice(wstEthPrice, asset);
        }

        AggregatorInfo memory aggregatorInfo = aggregators[asset];
        uint256 price = getPriceFromChainlink(aggregatorInfo.base, aggregatorInfo.quote);
        if (aggregatorInfo.quote == Denominations.ETH) {
            // Convert the price to USD based if it's ETH based.
            uint256 ethUsdPrice = getPriceFromChainlink(Denominations.ETH, Denominations.USD);
            price = (price * ethUsdPrice) / 1e18;
        }
        return getNormalizedPrice(price, asset);
    }

    /**
     * @notice Get price from Chainlink.
     * @param base The base asset
     * @param quote The quote asset
     * @return The price
     */
    function getPriceFromChainlink(address base, address quote) internal view returns (uint256) {
        (, int256 price,,,) = registry.latestRoundData(base, quote);
        require(price > 0, "invalid price");

        // Extend the decimals to 1e18.
        return uint256(price) * 10 ** (18 - uint256(registry.decimals(base, quote)));
    }

    /**
     * @dev Get the normalized price.
     * @param price The price
     * @param asset The asset
     * @return The normalized price
     */
    function getNormalizedPrice(uint256 price, address asset) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(asset).decimals();
        return price * 10 ** (18 - decimals);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    struct Aggregator {
        address asset;
        address base;
        address quote;
    }

    /**
     * @notice Set the aggregators.
     * @param aggrs The aggregators
     */
    function _setAggregators(Aggregator[] calldata aggrs) external onlyOwner {
        uint256 length = aggrs.length;
        for (uint256 i = 0; i < length;) {
            if (aggrs[i].base != address(0)) {
                require(aggrs[i].quote == Denominations.ETH || aggrs[i].quote == Denominations.USD, "unsupported quote");

                // Make sure the aggregator works.
                address aggregator = address(registry.getFeed(aggrs[i].base, aggrs[i].quote));
                require(registry.isFeedEnabled(aggregator), "aggregator not enabled");

                (, int256 price,,,) = registry.latestRoundData(aggrs[i].base, aggrs[i].quote);
                require(price > 0, "invalid price");
            }
            aggregators[aggrs[i].asset] = AggregatorInfo({base: aggrs[i].base, quote: aggrs[i].quote});

            unchecked {
                i++;
            }
        }
    }
}
