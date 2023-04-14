// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./Constants.sol";
import "./IronBankStorage.sol";
import "../../interfaces/IBTokenInterface.sol";
import "../../interfaces/IronBankInterface.sol";

contract MarketConfigurator is Ownable2Step, Constants {
    address private immutable _pool;

    address private _guardian;

    event GuardianSet(address guardian);
    event MarketCollateralFactorSet(address market, uint16 collateralFactor);
    event MarketLiquidationThresholdSet(address market, uint16 liquidationThreshold);
    event MarketLiquidationBonusSet(address market, uint16 liquidationBonus);
    event MarketReserveFactorSet(address market, uint16 reserveFactor);
    event MarketInterestRateModelSet(address market, address interestRateModel);
    event MarketSupplyCapSet(address market, uint256 cap);
    event MarketBorrowCapSet(address market, uint256 cap);
    event MarketPausedSet(address market, string action, bool paused);
    event MarketFrozen(address market, bool state);

    constructor(address pool_) {
        _pool = pool_;
    }

    modifier onlyOwnerOrGuardian() {
        _checkOwnerOrGuardian();
        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function getPool() external view returns (address) {
        return _pool;
    }

    function getGuardian() external view returns (address) {
        return _guardian;
    }

    function getMarketConfiguration(address market) public view returns (IronBankStorage.MarketConfig memory) {
        return IronBankInterface(_pool).getMarketConfiguration(market);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setGuardian(address guardian) external onlyOwner {
        _guardian = guardian;

        emit GuardianSet(guardian);
    }

    function listMarket(
        address market,
        address ibTokenAddress,
        address debtTokenAddress,
        address interestRateModelAddress,
        uint16 reserveFactor
    ) external onlyOwner {
        IronBankStorage.MarketConfig memory config = getMarketConfiguration(market);
        require(!config.isListed, "already listed");
        require(IBTokenInterface(ibTokenAddress).getUnderlying() == market, "mismatch underlying");
        require(IBTokenInterface(debtTokenAddress).getUnderlying() == market, "mismatch underlying");
        require(reserveFactor <= MAX_RESERVE_FACTOR, "invalid reserve factor");

        uint8 underlyingDecimals = IERC20Metadata(market).decimals();
        require(underlyingDecimals <= 18, "nonstandard token decimals");

        config.isListed = true;
        config.ibTokenAddress = ibTokenAddress;
        config.debtTokenAddress = debtTokenAddress;
        config.interestRateModelAddress = interestRateModelAddress;
        config.reserveFactor = reserveFactor;
        config.initialExchangeRate = 10 ** underlyingDecimals;

        IronBankInterface(_pool).listMarket(market, config);
    }

    function configureMarketAsCollateral(
        address market,
        uint16 collateralFactor,
        uint16 liquidationThreshold,
        uint16 liquidationBonus
    ) external onlyOwner {
        IronBankStorage.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");
        require(collateralFactor > 0 && collateralFactor <= MAX_COLLATETAL_FACTOR, "invalid collateral factor");
        require(
            liquidationThreshold > 0 && liquidationThreshold <= MAX_LIQUIDATION_THRESHOLD,
            "invalid liquidation threshold"
        );
        require(
            liquidationBonus > MIN_LIQUIDATION_BONUS && liquidationBonus <= MAX_LIQUIDATION_BONUS,
            "invalid liquidation bonus"
        );

        config.collateralFactor = collateralFactor;
        config.liquidationThreshold = liquidationThreshold;
        config.liquidationBonus = liquidationBonus;
        IronBankInterface(_pool).setMarketConfiguration(market, config);

        emit MarketCollateralFactorSet(market, collateralFactor);
        emit MarketLiquidationThresholdSet(market, liquidationThreshold);
        emit MarketLiquidationBonusSet(market, liquidationBonus);
    }

    function adjustMarketCollateralFactor(address market, uint16 collateralFactor) external onlyOwner {
        IronBankStorage.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");
        require(collateralFactor <= MAX_COLLATETAL_FACTOR, "invalid collateral factor");

        config.collateralFactor = collateralFactor;
        IronBankInterface(_pool).setMarketConfiguration(market, config);

        emit MarketCollateralFactorSet(market, collateralFactor);
    }

    function adjustMarketReserveFactor(address market, uint16 reserveFactor) external onlyOwner {
        IronBankStorage.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");
        require(reserveFactor <= MAX_RESERVE_FACTOR, "invalid reserve factor");

        config.reserveFactor = reserveFactor;
        IronBankInterface(_pool).setMarketConfiguration(market, config);

        emit MarketReserveFactorSet(market, reserveFactor);
    }

    function adjustLiquidationThreshold(address market, uint16 liquidationThreshold) external onlyOwner {
        IronBankStorage.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");
        require(
            liquidationThreshold > 0 && liquidationThreshold <= MAX_LIQUIDATION_THRESHOLD,
            "invalid liquidation threshold"
        );

        config.liquidationThreshold = liquidationThreshold;
        IronBankInterface(_pool).setMarketConfiguration(market, config);

        emit MarketLiquidationThresholdSet(market, liquidationThreshold);
    }

    function adjustLiquidationBonus(address market, uint16 liquidationBonus) external onlyOwner {
        IronBankStorage.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");
        require(
            liquidationBonus > MIN_LIQUIDATION_BONUS && liquidationBonus <= MAX_LIQUIDATION_BONUS,
            "invalid liquidation bonus"
        );

        config.liquidationBonus = liquidationBonus;
        IronBankInterface(_pool).setMarketConfiguration(market, config);

        emit MarketLiquidationBonusSet(market, liquidationBonus);
    }

    function changeMarketInterestRateModel(address market, address interestRateModelAddress) external onlyOwner {
        IronBankStorage.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");

        // Accrue interests before changing IRM.
        IronBankInterface(_pool).accrueInterest(market);

        config.interestRateModelAddress = interestRateModelAddress;
        IronBankInterface(_pool).setMarketConfiguration(market, config);

        emit MarketInterestRateModelSet(market, interestRateModelAddress);
    }

    function freezeMarket(address market, bool state) external onlyOwner {
        IronBankStorage.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");

        config.isFrozen = state;
        IronBankInterface(_pool).setMarketConfiguration(market, config);

        emit MarketFrozen(market, state);
    }

    function softDelistMarket(address market) external onlyOwner {
        IronBankStorage.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");

        if (!config.supplyPaused) {
            config.supplyPaused = true;
            emit MarketPausedSet(market, "supply", true);
        }
        if (!config.borrowPaused) {
            config.borrowPaused = true;
            emit MarketPausedSet(market, "borrow", true);
        }
        if (config.reserveFactor != MAX_RESERVE_FACTOR) {
            config.reserveFactor = MAX_RESERVE_FACTOR;
            emit MarketReserveFactorSet(market, MAX_RESERVE_FACTOR);
        }
        if (config.collateralFactor != 0) {
            config.collateralFactor = 0;
            emit MarketCollateralFactorSet(market, 0);
        }
        IronBankInterface(_pool).setMarketConfiguration(market, config);
    }

    function hardDelistMarket(address market) external onlyOwner {
        IronBankStorage.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");
        require(config.supplyPaused && config.borrowPaused, "not paused");
        require(config.reserveFactor == MAX_RESERVE_FACTOR, "reserve factor not max");
        require(config.collateralFactor == 0, "collateral factor not zero");

        IronBankInterface(_pool).delistMarket(market);
    }

    struct MarketCap {
        address market;
        uint256 cap;
    }

    function setMarketSupplyCaps(MarketCap[] calldata marketCaps) external onlyOwnerOrGuardian {
        uint256 length = marketCaps.length;
        for (uint256 i = 0; i < length;) {
            address market = marketCaps[i].market;
            uint256 cap = marketCaps[i].cap;
            IronBankStorage.MarketConfig memory config = getMarketConfiguration(market);
            require(config.isListed, "not listed");

            config.supplyCap = cap;
            IronBankInterface(_pool).setMarketConfiguration(market, config);

            emit MarketSupplyCapSet(market, cap);

            unchecked {
                i++;
            }
        }
    }

    function setMarketBorrowCaps(MarketCap[] calldata marketCaps) external onlyOwnerOrGuardian {
        uint256 length = marketCaps.length;
        for (uint256 i = 0; i < length;) {
            address market = marketCaps[i].market;
            uint256 cap = marketCaps[i].cap;
            IronBankStorage.MarketConfig memory config = getMarketConfiguration(market);
            require(config.isListed, "not listed");

            config.borrowCap = cap;
            IronBankInterface(_pool).setMarketConfiguration(market, config);

            emit MarketBorrowCapSet(market, cap);

            unchecked {
                i++;
            }
        }
    }

    function setSupplyPaused(address market, bool paused) external onlyOwnerOrGuardian {
        IronBankStorage.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");

        config.supplyPaused = paused;
        IronBankInterface(_pool).setMarketConfiguration(market, config);

        emit MarketPausedSet(market, "supply", paused);
    }

    function setBorrowPaused(address market, bool paused) external onlyOwnerOrGuardian {
        IronBankStorage.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");

        config.borrowPaused = paused;
        IronBankInterface(_pool).setMarketConfiguration(market, config);

        emit MarketPausedSet(market, "borrow", paused);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _checkOwnerOrGuardian() internal view {
        require(msg.sender == owner() || msg.sender == _guardian, "unauthorized");
    }
}
