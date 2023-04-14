# Iron Bank v2

## Getting started

1. Clone the repo.
2. Install [foundry](https://github.com/foundry-rs/foundry).

## Protocol contracts

### Core

- [IronBank.sol](https://github.com/ibdotxyz/ib-v2/blob/main/src/protocol/pool/IronBank.sol) - The core implementation of IB v2.
- [MarketConfigurator.sol](https://github.com/ibdotxyz/ib-v2/blob/main/src/protocol/pool/MarketConfigurator.sol) - The admin contract that configures the support markets.
- [CreditLimitManager.sol](https://github.com/ibdotxyz/ib-v2/blob/main/src/protocol/pool/CreditLimitManager.sol) - The admin contract that controls the credit limit.
- [IBToken.sol](https://github.com/ibdotxyz/ib-v2/blob/main/src/protocol/token/IBToken.sol) - The recipt contract that represents user supply.
- [DebtToken.sol](https://github.com/ibdotxyz/ib-v2/blob/main/src/protocol/token/DebtToken.sol) - The debt contract that represents user borrow.
- [TripleSlopeRateModel.sol](https://github.com/ibdotxyz/ib-v2/blob/main/src/protocol/pool/interest-rate-model/TripleSlopeRateModel.sol) - The interest rate model contract that calculates the supply and borrow rate.
- [PriceOracle.sol](https://github.com/ibdotxyz/ib-v2/blob/main/src/protocol/oracle/PriceOracle.sol) - The price oracle contract that fetches the prices from ChainLink.
- [IronBankLens.sol](https://github.com/ibdotxyz/ib-v2/blob/main/src/protocol/lens/IronBankLens.sol) - The lens contract that provides some useful on-chain data of IB v2.

### Extensions

- [IronBankExtension.sol](https://github.com/ibdotxyz/ib-v2/blob/main/src/extensions/IronBankExtension.sol) - The extension contract that supports native token, leverage, debt swap, and collateral swap.

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
$ forge test
```

Run specific test.

```
$ forge test --match-path test/TestSupply.t.sol
```

Display test coverage.

```
$ forge coverage
```
