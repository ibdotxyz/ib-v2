![GitHub CI](https://github.com/ibdotxyz/ib-v2/actions/workflows/test.yml/badge.svg)

# Iron Bank v2

## Getting started

1. Clone the repo.
2. Install [foundry](https://github.com/foundry-rs/foundry).

## Protocol contracts

### Core

- [IronBank.sol](https://github.com/ibdotxyz/ib-v2/blob/eth/src/protocol/pool/IronBank.sol) - The core implementation of IB v2.
- [MarketConfigurator.sol](https://github.com/ibdotxyz/ib-v2/blob/eth/src/protocol/pool/MarketConfigurator.sol) - The admin contract that configures the support markets.
- [CreditLimitManager.sol](https://github.com/ibdotxyz/ib-v2/blob/eth/src/protocol/pool/CreditLimitManager.sol) - The admin contract that controls the credit limit.
- [IBToken.sol](https://github.com/ibdotxyz/ib-v2/blob/eth/src/protocol/token/IBToken.sol) - The recipt contract that represents user supply.
- [DebtToken.sol](https://github.com/ibdotxyz/ib-v2/blob/eth/src/protocol/token/DebtToken.sol) - The debt contract that represents user borrow.
- [PToken.sol](https://github.com/ibdotxyz/ib-v2/blob/eth/src/protocol/token/PToken.sol) - The pToken contract that could only be used as collateral.
- [TripleSlopeRateModel.sol](https://github.com/ibdotxyz/ib-v2/blob/eth/src/protocol/pool/interest-rate-model/TripleSlopeRateModel.sol) - The interest rate model contract that calculates the supply and borrow rate.
- [PriceOracle.sol](https://github.com/ibdotxyz/ib-v2/blob/eth/src/protocol/oracle/PriceOracle.sol) - The price oracle contract that fetches the prices from ChainLink.
- [IronBankLens.sol](https://github.com/ibdotxyz/ib-v2/blob/eth/src/protocol/lens/IronBankLens.sol) - The lens contract that provides some useful on-chain data of IB v2.

### Extensions

- [TxBuilderExtension.sol](https://github.com/ibdotxyz/ib-v2/blob/eth/src/extensions/TxBuilderExtension.sol) - The extension contract that could help users perform multiple operations in a single transaction.
- [UniswapExtension.sol](https://github.com/ibdotxyz/ib-v2/blob/eth/src/extensions/UniswapExtension.sol) - The extension contract that supports leverage, debt swap, and collateral swap.

### FlashLoan

- [FlashLoan.sol](https://github.com/ibdotxyz/ib-v2/blob/eth/src/flashLoan/FlashLoan.sol) - The flashLoan contract that complies ERC-3156.

## Usage

### Compile contracts

```
$ forge build
```

Display contract size.

```
$ forge build --sizes
```

### Test contracts

Extension tests are using mainnet forking. Need to export the alchemy key to environment first.

```
export ALCHEMY_KEY=xxxxxx
```

Run all the tests.

```
$ forge test -vvv
```

Run specific test.

```
$ forge test -vvv --match-path test/TestSupply.t.sol
```

Display test coverage.

```
$ forge coverage
```

Display test coverage in lcov.

```
$ forge coverage --report lcov
$ genhtml -o report --branch-coverage lcov.info
```
