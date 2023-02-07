// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import "chainlink/contracts/src/v0.8/Denominations.sol";
import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "../../interfaces/PriceOracleInterface.sol";

contract PriceOracle is Ownable2Step, PriceOracleInterface {
    FeedRegistryInterface public immutable registry;

    struct AggregatorInfo {
        address base;
        address quote;
    }

    mapping(address => AggregatorInfo) public aggregators;

    string public constant QUOTE_SYMBOL = "USD";

    constructor(address registry_) {
        registry = FeedRegistryInterface(registry_);
    }

    function getPrice(address asset) external view returns (uint256) {
        AggregatorInfo memory aggregatorInfo = aggregators[asset];
        uint256 price = getPriceFromChainlink(aggregatorInfo.base, aggregatorInfo.quote);
        if (aggregatorInfo.quote == Denominations.ETH) {
            // Convert the price to USD based if it's ETH based.
            uint256 ethUsdPrice = getPriceFromChainlink(Denominations.ETH, Denominations.USD);
            price = (price * ethUsdPrice) / 1e18;
        }
        return price;
    }

    function getPriceFromChainlink(address base, address quote) internal view returns (uint256) {
        (, int256 price,,,) = registry.latestRoundData(base, quote);
        require(price > 0, "invalid price");

        // Extend the decimals to 1e18.
        return uint256(price) * 10 ** (18 - uint256(registry.decimals(base, quote)));
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    struct Aggregator {
        address asset;
        address base;
        address quote;
    }

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
