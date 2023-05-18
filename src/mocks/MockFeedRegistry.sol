// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";

contract MockFeedRegistry {
    uint80 public constant roundId = 1;

    mapping(address => mapping(address => int256)) private answer;
    bool public getFeedFailed;
    bool public feedDisabled;

    function latestRoundData(address base, address quote)
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (roundId, answer[base][quote], block.timestamp, block.timestamp, roundId);
    }

    function decimals(address base, address quote) external view returns (uint8) {
        base;
        quote;
        answer;

        return 8;
    }

    function setAnswer(address base, address quote, int256 _answer) external {
        answer[base][quote] = _answer;
    }
}
