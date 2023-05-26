// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./IronBankStorage.sol";
import "../../interfaces/DeferLiquidityCheckInterface.sol";
import "../../interfaces/IBTokenInterface.sol";
import "../../interfaces/InterestRateModelInterface.sol";
import "../../interfaces/IronBankInterface.sol";
import "../../interfaces/PriceOracleInterface.sol";
import "../../libraries/Arrays.sol";
import "../../libraries/DataTypes.sol";
import "../../libraries/PauseFlags.sol";

contract IronBank is
    Initializable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuard,
    IronBankStorage,
    IronBankInterface
{
    using SafeERC20 for IERC20;
    using Arrays for address[];
    using PauseFlags for DataTypes.MarketConfig;

    /**
     * @notice Initialize the contract.
     */
    function initialize(address _admin) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        transferOwnership(_admin);
    }

    /**
     * @notice Check if the caller is the market configurator.
     */
    modifier onlyMarketConfigurator() {
        _checkMarketConfigurator();
        _;
    }

    /**
     * @notice Check if the caller is the reserve manager.
     */
    modifier onlyReserveManager() {
        _checkReserveManager();
        _;
    }

    /**
     * @notice Check if the caller is the credit limit manager.
     */
    modifier onlyCreditLimitManager() {
        require(msg.sender == creditLimitManager, "!manager");
        _;
    }

    /**
     * @notice Check if the user has authorized the caller.
     */
    modifier isAuthorized(address from) {
        _checkAuthorized(from, msg.sender);
        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Get all markets.
     * @return The list of all markets
     */
    function getAllMarkets() public view returns (address[] memory) {
        return allMarkets;
    }

    /**
     * @notice Whether or not a market is listed.
     * @param market The address of the market to check
     * @return true if the market is listed, false otherwise
     */
    function isMarketListed(address market) public view returns (bool) {
        DataTypes.Market storage m = markets[market];
        return m.config.isListed;
    }

    /**
     * @notice Get the exchange rate of a market.
     * @param market The address of the market
     * @return The exchange rate
     */
    function getExchangeRate(address market) public view returns (uint256) {
        DataTypes.Market storage m = markets[market];
        return _getExchangeRate(m);
    }

    /**
     * @notice Get the total supply of a market.
     * @param market The address of the market
     * @return The total supply
     */
    function getTotalSupply(address market) public view returns (uint256) {
        DataTypes.Market storage m = markets[market];
        return m.totalSupply;
    }

    /**
     * @notice Get the total borrow of a market.
     * @param market The address of the market
     * @return The total borrow
     */
    function getTotalBorrow(address market) public view returns (uint256) {
        DataTypes.Market storage m = markets[market];
        return m.totalBorrow;
    }

    /**
     * @notice Get the total cash of a market.
     * @param market The address of the market
     * @return The total cash
     */
    function getTotalCash(address market) public view returns (uint256) {
        DataTypes.Market storage m = markets[market];
        return m.totalCash;
    }

    /**
     * @notice Get the total reserves of a market.
     * @param market The address of the market
     * @return The total reserves
     */
    function getTotalReserves(address market) public view returns (uint256) {
        DataTypes.Market storage m = markets[market];
        return m.totalReserves;
    }

    /**
     * @notice Get the borrow balance of a user in a market.
     * @param user The address of the user
     * @param market The address of the market
     * @return The borrow balance
     */
    function getBorrowBalance(address user, address market) public view returns (uint256) {
        DataTypes.Market storage m = markets[market];
        return _getBorrowBalance(m, user);
    }

    /**
     * @notice Get the IBToken balance of a user in a market.
     * @param user The address of the user
     * @param market The address of the market
     * @return The IBToken balance
     */
    function getIBTokenBalance(address user, address market) public view returns (uint256) {
        DataTypes.Market storage m = markets[market];
        return m.userSupplies[user];
    }

    /**
     * @notice Get the supply balance of a user in a market.
     * @param user The address of the user
     * @param market The address of the market
     * @return The supply balance
     */
    function getSupplyBalance(address user, address market) public view returns (uint256) {
        DataTypes.Market storage m = markets[market];
        return (m.userSupplies[user] * _getExchangeRate(m)) / 1e18;
    }

    /**
     * @notice Get the account liquidity of a user.
     * @param user The address of the user
     * @return The account collateral value and borrow value
     */
    function getAccountLiquidity(address user) public view returns (uint256, uint256) {
        return _getAccountLiquidity(user);
    }

    /**
     * @notice Get the user's entered markets.
     * @param user The address of the user
     * @return The list of entered markets
     */
    function getUserEnteredMarkets(address user) public view returns (address[] memory) {
        return allEnteredMarkets[user];
    }

    /**
     * @notice Get the user's allowed extensions.
     * @param user The address of the user
     * @return The list of allowed extensions
     */
    function getUserAllowedExtensions(address user) public view returns (address[] memory) {
        return allAllowedExtensions[user];
    }

    /**
     * @notice Whether or not a user has allowed an extension.
     * @param user The address of the user
     * @param extension The address of the extension
     * @return true if the user has allowed the extension, false otherwise
     */
    function isAllowedExtension(address user, address extension) public view returns (bool) {
        return allowedExtensions[user][extension];
    }

    /**
     * @notice Get the credit limit of a user in a market.
     * @param user The address of the user
     * @param market The address of the market
     * @return The credit limit
     */
    function getCreditLimit(address user, address market) public view returns (uint256) {
        return creditLimits[user][market];
    }

    /**
     * @notice Get the list of all credit markets for a user.
     * @param user The address of the user
     * @return The list of all credit markets
     */
    function getUserCreditMarkets(address user) public view returns (address[] memory) {
        return allCreditMarkets[user];
    }

    /**
     * @notice Whether or not an account is a credit account.
     * @param user The address of the user
     * @return true if the account is a credit account, false otherwise
     */
    function isCreditAccount(address user) public view returns (bool) {
        return allCreditMarkets[user].length > 0;
    }

    /**
     * @notice Get the configuration of a market.
     * @param market The address of the market
     * @return The market configuration
     */
    function getMarketConfiguration(address market) public view returns (DataTypes.MarketConfig memory) {
        return markets[market].config;
    }

    /**
     * @notice Check if an account is liquidatable.
     * @param user The address of the account to check
     * @return true if the account is liquidatable, false otherwise
     */
    function isUserLiquidatable(address user) public view returns (bool) {
        return _isLiquidatable(user);
    }

    /**
     * @notice Calculate the amount of ibToken that can be seized in a liquidation.
     * @param marketBorrow The address of the market being borrowed from
     * @param marketCollateral The address of the market being used as collateral
     * @param repayAmount The amount of the borrowed asset being repaid
     * @return The amount of ibToken that can be seized
     */
    function calculateLiquidationOpportunity(address marketBorrow, address marketCollateral, uint256 repayAmount)
        public
        view
        returns (uint256)
    {
        DataTypes.Market storage mCollateral = markets[marketCollateral];

        return _getLiquidationSeizeAmount(marketBorrow, marketCollateral, mCollateral, repayAmount);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Accrue the interest of a market.
     * @param market The address of the market
     */
    function accrueInterest(address market) external {
        DataTypes.Market storage m = markets[market];
        require(m.config.isListed, "not listed");

        _accrueInterest(market, m);
    }

    /**
     * @notice Check the account liquidity of a user.
     * @param user The address of the user
     */
    function checkAccountLiquidity(address user) public {
        _checkAccountLiquidity(user);
    }

    /**
     * @notice Supply an amount of asset to Iron Bank.
     * @param from The address which will supply the asset
     * @param to The address which will hold the balance
     * @param market The address of the market
     * @param amount The amount of asset to supply
     */
    function supply(address from, address to, address market, uint256 amount)
        external
        nonReentrant
        isAuthorized(from)
    {
        DataTypes.Market storage m = markets[market];
        require(m.config.isListed, "not listed");
        require(!m.config.isSupplyPaused(), "supply paused");
        require(!isCreditAccount(to), "cannot supply to credit account");

        _accrueInterest(market, m);

        if (m.config.supplyCap != 0) {
            uint256 totalSupplyUnderlying = m.totalSupply * _getExchangeRate(m) / 1e18;
            require(totalSupplyUnderlying + amount <= m.config.supplyCap, "supply cap reached");
        }

        uint256 ibTokenAmount = (amount * 1e18) / _getExchangeRate(m);

        // Update storage.
        m.totalCash += amount;
        m.totalSupply += ibTokenAmount;
        unchecked {
            // Overflow not possible: supplyBalance + ibTokenAmount is at most totalSupply + ibTokenAmount, which is checked above.
            m.userSupplies[to] += ibTokenAmount;
        }

        // Enter the market.
        if (amount > 0) {
            _enterMarket(market, to);
        }

        IBTokenInterface(m.config.ibTokenAddress).mint(to, ibTokenAmount); // Only emits Transfer event.
        IERC20(market).safeTransferFrom(from, address(this), amount);

        emit Supply(market, from, to, amount, ibTokenAmount);
    }

    /**
     * @notice Borrow an amount of asset from Iron Bank.
     * @param from The address which will borrow the asset
     * @param to The address which will receive the token
     * @param market The address of the market
     * @param amount The amount of asset to borrow
     */
    function borrow(address from, address to, address market, uint256 amount)
        external
        nonReentrant
        isAuthorized(from)
    {
        DataTypes.Market storage m = markets[market];
        require(m.config.isListed, "not listed");
        require(!m.config.isBorrowPaused(), "borrow paused");
        require(m.totalCash >= amount, "insufficient cash");

        _accrueInterest(market, m);

        uint256 newTotalBorrow = m.totalBorrow + amount;
        uint256 newUserBorrowBalance;
        unchecked {
            // Overflow not possible: borrowBalance + amount is at most totalBorrow + amount, which is checked above.
            newUserBorrowBalance = _getBorrowBalance(m, from) + amount;
        }

        if (m.config.borrowCap != 0) {
            require(newTotalBorrow <= m.config.borrowCap, "borrow cap reached");
        }

        // Update storage.
        unchecked {
            m.totalCash -= amount;
        }
        m.totalBorrow = newTotalBorrow;
        m.userBorrows[from].borrowBalance = newUserBorrowBalance;
        m.userBorrows[from].borrowIndex = m.borrowIndex;

        // Enter the market.
        if (amount > 0) {
            _enterMarket(market, from);
        }

        IERC20(market).safeTransfer(to, amount);

        if (isCreditAccount(from)) {
            require(from == to, "credit account can only borrow to itself");
            require(creditLimits[from][market] >= newUserBorrowBalance, "insufficient credit limit");
        } else {
            _checkAccountLiquidity(from);
        }

        emit Borrow(market, from, to, amount, newUserBorrowBalance, newTotalBorrow);
    }

    /**
     * @notice Redeem an amount of asset from Iron Bank.
     * @param from The address which will redeem the asset
     * @param to The address which will receive the token
     * @param market The address of the market
     * @param amount The amount of asset to redeem, or type(uint256).max for max
     */
    function redeem(address from, address to, address market, uint256 amount)
        external
        nonReentrant
        isAuthorized(from)
    {
        DataTypes.Market storage m = markets[market];
        require(m.config.isListed, "not listed");

        _accrueInterest(market, m);

        uint256 userSupply = m.userSupplies[from];
        uint256 totalCash = m.totalCash;

        uint256 ibTokenAmount;
        bool isRedeemFull;
        if (amount == type(uint256).max) {
            ibTokenAmount = userSupply;
            amount = (ibTokenAmount * _getExchangeRate(m)) / 1e18;
            isRedeemFull = true;
        } else {
            ibTokenAmount = (amount * 1e18) / _getExchangeRate(m);
        }

        require(userSupply >= ibTokenAmount, "insufficient balance");
        require(totalCash >= amount, "insufficient cash");

        // Update storage.
        unchecked {
            m.userSupplies[from] = userSupply - ibTokenAmount;
            m.totalCash = totalCash - amount;
            // Underflow not possible: ibTokenAmount <= userSupply <= totalSupply.
            m.totalSupply -= ibTokenAmount;
        }

        // Check if need to exit the market.
        if (isRedeemFull && _getBorrowBalance(m, from) == 0) {
            _exitMarket(market, from);
        }

        IBTokenInterface(m.config.ibTokenAddress).burn(from, ibTokenAmount); // Only emits Transfer event.
        IERC20(market).safeTransfer(to, amount);

        _checkAccountLiquidity(from);

        emit Redeem(market, from, to, amount, ibTokenAmount);
    }

    /**
     * @notice Repay an amount of asset to Iron Bank.
     * @param from The address which will repay the asset
     * @param to The address which will hold the balance
     * @param market The address of the market
     * @param amount The amount of asset to repay, or type(uint256).max for max
     */
    function repay(address from, address to, address market, uint256 amount) external nonReentrant isAuthorized(from) {
        DataTypes.Market storage m = markets[market];
        require(m.config.isListed, "not listed");
        if (isCreditAccount(to)) {
            require(from == to, "credit account can only repay for itself");
        }

        _accrueInterest(market, m);

        _repay(m, from, to, market, amount);
    }

    /**
     * @notice Liquidate an undercollateralized borrower.
     * @param liquidator The address which will liquidate the borrower
     * @param borrower The address of the borrower
     * @param marketBorrow The address of the borrow market
     * @param marketCollateral The address of the collateral market
     * @param repayAmount The amount of asset to repay, or type(uint256).max for max
     */
    function liquidate(
        address liquidator,
        address borrower,
        address marketBorrow,
        address marketCollateral,
        uint256 repayAmount
    ) external nonReentrant isAuthorized(liquidator) {
        DataTypes.Market storage mBorrow = markets[marketBorrow];
        DataTypes.Market storage mCollateral = markets[marketCollateral];
        require(mBorrow.config.isListed, "borrow market not listed");
        require(mCollateral.config.isListed, "collateral market not listed");
        require(isMarketSeizable(mCollateral), "collateral market cannot be seized");
        require(!isCreditAccount(borrower), "cannot liquidate credit account");
        require(liquidator != borrower, "cannot self liquidate");

        _accrueInterest(marketBorrow, mBorrow);
        _accrueInterest(marketCollateral, mCollateral);

        // Check if the borrower is actually liquidatable.
        require(_isLiquidatable(borrower), "borrower not liquidatable");

        // Repay the debt.
        repayAmount = _repay(mBorrow, liquidator, borrower, marketBorrow, repayAmount);

        // Seize the collateral.
        uint256 ibTokenAmount = _getLiquidationSeizeAmount(marketBorrow, marketCollateral, mCollateral, repayAmount);
        _transferIBToken(marketCollateral, mCollateral, borrower, liquidator, ibTokenAmount);
        IBTokenInterface(mCollateral.config.ibTokenAddress).seize(borrower, liquidator, ibTokenAmount); // Only emits Transfer event.

        emit Liquidate(liquidator, borrower, marketBorrow, marketCollateral, repayAmount, ibTokenAmount);
    }

    /**
     * @notice Defer the liquidity check to a user.
     * @dev The message sender must implement the DeferLiquidityCheckInterface.
     * @param user The address of the user
     * @param data The data to pass to the callback
     */
    function deferLiquidityCheck(address user, bytes memory data) external {
        require(!isCreditAccount(user), "credit account cannot defer liquidity check");
        require(liquidityCheckStatus[user] == LIQUIDITY_CHECK_NORMAL, "reentry defer liquidity check");
        liquidityCheckStatus[user] = LIQUIDITY_CHECK_DEFERRED;

        DeferLiquidityCheckInterface(msg.sender).onDeferredLiquidityCheck(data);

        uint8 status = liquidityCheckStatus[user];
        liquidityCheckStatus[user] = LIQUIDITY_CHECK_NORMAL;

        if (status == LIQUIDITY_CHECK_DIRTY) {
            _checkAccountLiquidity(user);
        }
    }

    /**
     * @notice User enables or disables an extension.
     * @param extension The address of the extension
     * @param allowed Whether to allow or disallow the extension
     */
    function setUserExtension(address extension, bool allowed) external {
        if (allowed && !allowedExtensions[msg.sender][extension]) {
            allowedExtensions[msg.sender][extension] = true;
            allAllowedExtensions[msg.sender].push(extension);

            emit ExtensionAdded(msg.sender, extension);
        } else if (!allowed && allowedExtensions[msg.sender][extension]) {
            allowedExtensions[msg.sender][extension] = false;
            allAllowedExtensions[msg.sender].deleteElement(extension);

            emit ExtensionRemoved(msg.sender, extension);
        }
    }

    /**
     * @notice Transfer IBToken from one account to another.
     * @dev This function is callable by the IBToken contract only.
     * @param market The address of the market
     * @param from The address to transfer from
     * @param to The address to transfer to
     * @param amount The amount to transfer
     */
    function transferIBToken(address market, address from, address to, uint256 amount) external {
        DataTypes.Market storage m = markets[market];
        require(m.config.isListed, "not listed");
        require(msg.sender == m.config.ibTokenAddress, "!authorized");
        require(!m.config.isTransferPaused(), "transfer paused");
        require(from != to, "cannot self transfer");
        require(!isCreditAccount(to), "cannot transfer to credit account");

        _accrueInterest(market, m);
        _transferIBToken(market, m, from, to, amount);

        _checkAccountLiquidity(from);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice List a market.
     * @dev This function is callable by the market configurator only.
     * @param market The address of the market
     * @param config The market configuration
     */
    function listMarket(address market, DataTypes.MarketConfig calldata config) external onlyMarketConfigurator {
        DataTypes.Market storage m = markets[market];
        require(!m.config.isListed, "already listed");

        m.lastUpdateTimestamp = _getNow();
        m.borrowIndex = INITIAL_BORROW_INDEX;
        m.config = config;
        allMarkets.push(market);

        emit MarketListed(market, m.lastUpdateTimestamp, m.config);
    }

    /**
     * @notice Delist a market.
     * @dev This function is callable by the market configurator only.
     * @param market The address of the market
     */
    function delistMarket(address market) external onlyMarketConfigurator {
        DataTypes.Market storage m = markets[market];
        require(m.config.isListed, "not listed");

        delete markets[market];
        allMarkets.deleteElement(market);

        emit MarketDelisted(market);
    }

    /**
     * @notice Set the market configuration.
     * @dev This function is callable by the market configurator only.
     * @param market The address of the market
     * @param config The market configuration
     */
    function setMarketConfiguration(address market, DataTypes.MarketConfig calldata config)
        external
        onlyMarketConfigurator
    {
        DataTypes.Market storage m = markets[market];
        require(m.config.isListed, "not listed");

        m.config = config;

        emit MarketConfigurationChanged(market, config);
    }

    /**
     * @notice Set the credit limit for a user in a market.
     * @dev This function is callable by the credit limit manager only.
     * @param user The address of the user
     * @param market The address of the market
     * @param credit The credit limit
     */
    function setCreditLimit(address user, address market, uint256 credit) external onlyCreditLimitManager {
        DataTypes.Market storage m = markets[market];
        require(m.config.isListed, "not listed");

        if (credit == 0 && creditLimits[user][market] != 0) {
            allCreditMarkets[user].deleteElement(market);
        } else if (credit != 0 && creditLimits[user][market] == 0) {
            allCreditMarkets[user].push(market);
        }

        creditLimits[user][market] = credit;
        emit CreditLimitChanged(user, market, credit);
    }

    /**
     * @notice Increase reserves by absorbing the surplus cash.
     * @dev This function is callable by the reserve manager only.
     * @param market The address of the market
     */
    function absorbToReserves(address market) external onlyReserveManager {
        DataTypes.Market storage m = markets[market];
        require(m.config.isListed, "not listed");

        _accrueInterest(market, m);

        uint256 amount = IERC20(market).balanceOf(address(this)) - m.totalCash;

        if (amount > 0) {
            uint256 ibTokenAmount = (amount * 1e18) / _getExchangeRate(m);

            // Update internal cash, and total reserves.
            m.totalCash += amount;
            m.totalReserves += ibTokenAmount;

            emit ReservesIncreased(market, ibTokenAmount, amount);
        }
    }

    /**
     * @notice Reduce reserves by withdrawing the requested amount.
     * @dev This function is callable by the reserve manager only.
     * @param market The address of the market
     * @param ibTokenAmount The amount of ibToken to withdraw
     * @param recipient The address which will receive the underlying asset
     */
    function reduceReserves(address market, uint256 ibTokenAmount, address recipient) external onlyReserveManager {
        DataTypes.Market storage m = markets[market];
        require(m.config.isListed, "not listed");

        _accrueInterest(market, m);

        uint256 amount = (ibTokenAmount * _getExchangeRate(m)) / 1e18;

        require(m.totalCash >= amount, "insufficient cash");
        require(m.totalReserves >= ibTokenAmount, "insufficient reserves");

        // Update internal cash, and total reserves.
        unchecked {
            m.totalCash -= amount;
            m.totalReserves -= ibTokenAmount;
        }

        IERC20(market).safeTransfer(recipient, amount);

        emit ReservesDecreased(market, recipient, ibTokenAmount, amount);
    }

    /**
     * @notice Set the price oracle.
     * @param oracle The address of the price oracle
     */
    function setPriceOracle(address oracle) external onlyOwner {
        priceOracle = oracle;

        emit PriceOracleSet(oracle);
    }

    /**
     * @notice Set the market configurator.
     * @param configurator The address of the market configurator
     */
    function setMarketConfigurator(address configurator) external onlyOwner {
        marketConfigurator = configurator;

        emit MarketConfiguratorSet(configurator);
    }

    /**
     * @notice Set the credit limit manager.
     * @param manager The address of the credit limit manager
     */
    function setCreditLimitManager(address manager) external onlyOwner {
        creditLimitManager = manager;

        emit CreditLimitManagerSet(manager);
    }

    /**
     * @notice Set the reserve manager.
     * @param manager The address of the reserve manager
     */
    function setReserveManager(address manager) external onlyOwner {
        reserveManager = manager;

        emit ReserveManagerSet(manager);
    }

    /**
     * @notice Seize the unlisted token.
     * @param token The address of the token
     * @param recipient The address which will receive the token
     */
    function seize(address token, address recipient) external onlyOwner {
        DataTypes.Market storage m = markets[token];
        require(!m.config.isListed, "cannot seize listed market");

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(recipient, balance);

            emit TokenSeized(token, recipient, balance);
        }
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev _authorizeUpgrade is used by UUPSUpgradeable to determine if it's allowed to upgrade a proxy implementation.
     * @param newImplementation The new implementation
     *
     * Ref: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/utils/UUPSUpgradeable.sol
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Get the current timestamp.
     * @return The current timestamp, casted to uint40
     */
    function _getNow() internal view virtual returns (uint40) {
        require(block.timestamp < 2 ** 40, "timestamp too large");
        return uint40(block.timestamp);
    }

    /**
     * @dev Check if the operator is authorized.
     * @param from The address of the user
     * @param operator The address of the operator
     */
    function _checkAuthorized(address from, address operator) internal view {
        require(from == operator || (!isCreditAccount(from) && isAllowedExtension(from, operator)), "!authorized");
    }

    /**
     * @dev Check if the message sender is the market configurator.
     */
    function _checkMarketConfigurator() internal view {
        require(msg.sender == marketConfigurator, "!configurator");
    }

    /**
     * @dev Check if the message sender is the credit limit manager.
     */
    function _checkReserveManager() internal view {
        require(msg.sender == reserveManager, "!reserveManager");
    }

    /**
     * @dev Get the exchange rate.
     * @param m The storage of the market
     * @return The exchange rate
     */
    function _getExchangeRate(DataTypes.Market storage m) internal view returns (uint256) {
        uint256 totalSupplyPlusReserves = m.totalSupply + m.totalReserves;
        if (totalSupplyPlusReserves == 0) {
            return m.config.initialExchangeRate;
        }
        return ((m.totalCash + m.totalBorrow) * 1e18) / totalSupplyPlusReserves;
    }

    /**
     * @dev Get the amount of ibToken that can be seized in a liquidation.
     * @param marketBorrow The address of the market being borrowed from
     * @param marketCollateral The address of the market being used as collateral
     * @param mCollateral The storage of the collateral market
     * @param repayAmount The amount of the borrowed asset being repaid
     * @return The amount of ibToken that can be seized
     */
    function _getLiquidationSeizeAmount(
        address marketBorrow,
        address marketCollateral,
        DataTypes.Market storage mCollateral,
        uint256 repayAmount
    ) internal view returns (uint256) {
        uint256 borrowMarketPrice = PriceOracleInterface(priceOracle).getPrice(marketBorrow);
        uint256 collateralMarketPrice = PriceOracleInterface(priceOracle).getPrice(marketCollateral);
        require(borrowMarketPrice > 0 && collateralMarketPrice > 0, "invalid price");

        // collateral amount = repayAmount * liquidationBonus * borrowMarketPrice / collateralMarketPrice
        // IBToken amount = collateral amount / exchangeRate
        //   = repayAmount * (liquidationBonus * borrowMarketPrice) / (collateralMarketPrice * exchangeRate)
        uint256 numerator = (mCollateral.config.liquidationBonus * borrowMarketPrice) / FACTOR_SCALE;
        uint256 denominator = (_getExchangeRate(mCollateral) * collateralMarketPrice) / 1e18;

        return (repayAmount * numerator) / denominator;
    }

    /**
     * @dev Get the borrow balance of a user.
     * @param m The storage of the market
     * @param user The address of the user
     * @return The borrow balance
     */
    function _getBorrowBalance(DataTypes.Market storage m, address user) internal view returns (uint256) {
        DataTypes.UserBorrow memory b = m.userBorrows[user];

        if (b.borrowBalance == 0) {
            return 0;
        }

        // borrowBalanceWithInterests = borrowBalance * marketBorrowIndex / userBorrowIndex
        return (b.borrowBalance * m.borrowIndex) / b.borrowIndex;
    }

    /**
     * @dev Transfer IBToken from one account to another.
     * @param market The address of the market
     * @param m The storage of the market
     * @param from The address to transfer from
     * @param to The address to transfer to
     * @param amount The amount to transfer
     */
    function _transferIBToken(address market, DataTypes.Market storage m, address from, address to, uint256 amount)
        internal
    {
        require(from != address(0), "transfer from the zero address");
        require(to != address(0), "transfer to the zero address");

        uint256 fromBalance = m.userSupplies[from];
        require(amount > 0, "transfer zero amount");
        require(fromBalance >= amount, "transfer amount exceeds balance");

        _enterMarket(market, to);

        unchecked {
            m.userSupplies[from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            m.userSupplies[to] += amount;
        }

        if (m.userSupplies[from] == 0 && _getBorrowBalance(m, from) == 0) {
            _exitMarket(market, from);
        }
    }

    /**
     * @dev Accrue interest to the current timestamp.
     * @param market The address of the market
     * @param m The storage of the market
     */
    function _accrueInterest(address market, DataTypes.Market storage m) internal {
        uint40 timestamp = _getNow();
        uint256 timeElapsed = uint256(timestamp - m.lastUpdateTimestamp);
        if (timeElapsed > 0) {
            uint256 totalCash = m.totalCash;
            uint256 borrowIndex = m.borrowIndex;
            uint256 totalBorrow = m.totalBorrow;
            uint256 totalSupply = m.totalSupply;
            uint256 totalReserves = m.totalReserves;

            uint256 borrowRatePerSecond =
                InterestRateModelInterface(m.config.interestRateModelAddress).getBorrowRate(totalCash, totalBorrow);
            uint256 interestFactor = borrowRatePerSecond * timeElapsed;
            uint256 interestIncreased = (interestFactor * totalBorrow) / 1e18;
            uint256 feeIncreased = (interestIncreased * m.config.reserveFactor) / FACTOR_SCALE;

            // Compute reservesIncreased.
            uint256 reservesIncreased = 0;
            if (feeIncreased > 0) {
                reservesIncreased = (feeIncreased * (totalSupply + totalReserves))
                    / (totalCash + totalBorrow + (interestIncreased - feeIncreased));
            }

            // Compute new states.
            borrowIndex += (interestFactor * borrowIndex) / 1e18;
            totalBorrow += interestIncreased;
            totalReserves += reservesIncreased;

            // Update state variables.
            m.lastUpdateTimestamp = timestamp;
            m.borrowIndex = borrowIndex;
            m.totalBorrow = totalBorrow;
            m.totalReserves = totalReserves;

            emit InterestAccrued(market, timestamp, borrowRatePerSecond, borrowIndex, totalBorrow, totalReserves);
        }
    }

    /**
     * @dev Enter a market.
     * @param market The address of the market
     * @param user The address of the user
     */
    function _enterMarket(address market, address user) internal {
        if (enteredMarkets[user][market]) {
            // Skip if user has entered the market.
            return;
        }

        enteredMarkets[user][market] = true;
        allEnteredMarkets[user].push(market);

        emit MarketEntered(market, user);
    }

    /**
     * @dev Exit a market.
     * @param market The address of the market
     * @param user The address of the user
     */
    function _exitMarket(address market, address user) internal {
        if (!enteredMarkets[user][market]) {
            // Skip if user has not entered the market.
            return;
        }

        enteredMarkets[user][market] = false;
        allEnteredMarkets[user].deleteElement(market);

        emit MarketExited(market, user);
    }

    /**
     * @dev Repay an amount of asset to Iron Bank.
     * @param m The market object
     * @param from The address which will repay the asset
     * @param to The address which will hold the balance
     * @param market The address of the market
     * @param amount The amount of asset to repay, or type(uint256).max for max
     * @return The actual amount repaid
     */
    function _repay(DataTypes.Market storage m, address from, address to, address market, uint256 amount)
        internal
        returns (uint256)
    {
        uint256 borrowBalance = _getBorrowBalance(m, to);
        if (amount == type(uint256).max) {
            amount = borrowBalance;
        }

        require(amount <= borrowBalance, "repay too much");

        uint256 newUserBorrowBalance;
        uint256 newTotalBorrow;
        unchecked {
            newUserBorrowBalance = borrowBalance - amount;
            // Underflow not possible: amount <= userBorrow <= totalBorrow
            newTotalBorrow = m.totalBorrow - amount;
        }

        // Update storage.
        m.userBorrows[to].borrowBalance = newUserBorrowBalance;
        m.userBorrows[to].borrowIndex = m.borrowIndex;
        m.totalCash += amount;
        m.totalBorrow = newTotalBorrow;

        // Check if need to exit the market.
        if (m.userSupplies[to] == 0 && newUserBorrowBalance == 0) {
            _exitMarket(market, to);
        }

        IERC20(market).safeTransferFrom(from, address(this), amount);

        emit Repay(market, from, to, amount, newUserBorrowBalance, newTotalBorrow);

        return amount;
    }

    /**
     * @dev Check the account liquidity of a user. If the account liquidity check is deferred, mark the status to dirty. It must be checked later.
     * @param user The address of the user
     */
    function _checkAccountLiquidity(address user) internal {
        uint8 status = liquidityCheckStatus[user];

        if (status == LIQUIDITY_CHECK_NORMAL) {
            (uint256 collateralValue, uint256 debtValue) = _getAccountLiquidity(user);
            require(collateralValue >= debtValue, "insufficient collateral");
        } else if (status == LIQUIDITY_CHECK_DEFERRED) {
            liquidityCheckStatus[user] = LIQUIDITY_CHECK_DIRTY;
        }
    }

    /**
     * @dev Get the account liquidity of a user.
     * @param user The address of the user
     * @return The total collateral value and total debt value of the user
     */
    function _getAccountLiquidity(address user) internal view returns (uint256, uint256) {
        uint256 collateralValue;
        uint256 debtValue;

        address[] memory userEnteredMarkets = allEnteredMarkets[user];
        for (uint256 i = 0; i < userEnteredMarkets.length; i++) {
            DataTypes.Market storage m = markets[userEnteredMarkets[i]];
            if (!m.config.isListed) {
                continue;
            }

            uint256 supplyBalance = m.userSupplies[user];
            uint256 borrowBalance = _getBorrowBalance(m, user);

            uint256 assetPrice = PriceOracleInterface(priceOracle).getPrice(userEnteredMarkets[i]);
            require(assetPrice > 0, "invalid price");
            uint256 collateralFactor = m.config.collateralFactor;
            if (supplyBalance > 0 && collateralFactor > 0) {
                uint256 exchangeRate = _getExchangeRate(m);
                collateralValue += (supplyBalance * exchangeRate * assetPrice * collateralFactor) / 1e36 / FACTOR_SCALE;
            }
            if (borrowBalance > 0) {
                debtValue += (borrowBalance * assetPrice) / 1e18;
            }
        }
        return (collateralValue, debtValue);
    }

    /**
     * @dev Check if an account is liquidatable.
     * @param user The address of the account to check
     * @return true if the account is liquidatable, false otherwise
     */
    function _isLiquidatable(address user) internal view returns (bool) {
        uint256 liquidationCollateralValue;
        uint256 debtValue;

        address[] memory userEnteredMarkets = allEnteredMarkets[user];
        for (uint256 i = 0; i < userEnteredMarkets.length; i++) {
            DataTypes.Market storage m = markets[userEnteredMarkets[i]];
            if (!m.config.isListed) {
                continue;
            }

            uint256 supplyBalance = m.userSupplies[user];
            uint256 borrowBalance = _getBorrowBalance(m, user);

            uint256 assetPrice = PriceOracleInterface(priceOracle).getPrice(userEnteredMarkets[i]);
            require(assetPrice > 0, "invalid price");
            uint256 liquidationThreshold = m.config.liquidationThreshold;
            if (supplyBalance > 0 && liquidationThreshold > 0) {
                uint256 exchangeRate = _getExchangeRate(m);
                liquidationCollateralValue +=
                    (supplyBalance * exchangeRate * assetPrice * liquidationThreshold) / 1e36 / FACTOR_SCALE;
            }
            if (borrowBalance > 0) {
                debtValue += (borrowBalance * assetPrice) / 1e18;
            }
        }
        return debtValue > liquidationCollateralValue;
    }

    /**
     * @dev Check if a market is seizable when a liquidation happens.
     * @param m The market object
     * @return true if the market is seizable, false otherwise
     */
    function isMarketSeizable(DataTypes.Market storage m) internal view returns (bool) {
        return !m.config.isTransferPaused() && m.config.liquidationThreshold > 0;
    }
}
