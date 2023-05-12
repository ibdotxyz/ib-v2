// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/extensions/TxBuilderExtension.sol";
import "../src/extensions/UniswapExtension.sol";
import "../src/flashLoan/interfaces/IERC3156FlashBorrower.sol";
import "../src/flashLoan/FlashLoan.sol";
import "../src/interfaces/DeferLiquidityCheckInterface.sol";
import "../src/protocol/lens/IronBankLens.sol";
import "../src/protocol/oracle/PriceOracle.sol";
import "../src/protocol/pool/interest-rate-model/TripleSlopeRateModel.sol";
import "../src/protocol/pool/CreditLimitManager.sol";
import "../src/protocol/pool/Events.sol";
import "../src/protocol/pool/IronBank.sol";
import "../src/protocol/pool/IronBankProxy.sol";
import "../src/protocol/pool/MarketConfigurator.sol";
import "../src/protocol/token/IBToken.sol";
import "../src/protocol/token/DebtToken.sol";
import "../src/protocol/token/PToken.sol";
import "./MockToken.t.sol";
import "./MockPriceOracle.t.sol";
import "./MockFeedRegistry.t.sol";
import "./MockWstEth.t.sol";

abstract contract Common is Test, Events {
    function fastForwardBlocks(uint256 blocks) internal {
        vm.roll(block.number + blocks);
    }

    function fastForwardTime(uint256 timeInterval) internal {
        vm.warp(block.timestamp + timeInterval);
    }

    function constructMarketCapArgument(address market, uint256 cap)
        internal
        pure
        returns (MarketConfigurator.MarketCap[] memory)
    {
        MarketConfigurator.MarketCap[] memory caps = new MarketConfigurator.MarketCap[](1);
        caps[0] = MarketConfigurator.MarketCap({market: market, cap: cap});
        return caps;
    }

    function createIronBank(address _admin) internal returns (IronBank) {
        IronBank impl = new IronBank();
        IronBankProxy proxy = new IronBankProxy(address(impl), "");
        IronBank ib = IronBank(address(proxy));
        ib.initialize(_admin);
        vm.prank(_admin);
        ib.acceptOwnership();
        return ib;
    }

    function createMarketConfigurator(address _admin, IronBank _ironBank) internal returns (MarketConfigurator) {
        MarketConfigurator configurator = new MarketConfigurator(address(_ironBank));
        configurator.transferOwnership(_admin);
        vm.prank(_admin);
        configurator.acceptOwnership();
        return configurator;
    }

    function createCreditLimitManager(address _admin, IronBank _ironBank) internal returns (CreditLimitManager) {
        CreditLimitManager creditLimitManager = new CreditLimitManager(address(_ironBank));
        creditLimitManager.transferOwnership(_admin);
        vm.prank(_admin);
        creditLimitManager.acceptOwnership();
        return creditLimitManager;
    }

    function createIBToken(address _admin, address _pool, address _underlying) internal returns (IBToken) {
        IBToken impl = new IBToken();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        IBToken ibToken = IBToken(address(proxy));
        ibToken.initialize("Iron Bank Token", "ibToken", _admin, _pool, _underlying);
        return ibToken;
    }

    function createDebtToken(address _admin, address _pool, address _underlying) internal returns (DebtToken) {
        DebtToken impl = new DebtToken();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        DebtToken debtToken = DebtToken(address(proxy));
        debtToken.initialize("Iron Bank Debt Token", "debtToken", _admin, _pool, _underlying);
        return debtToken;
    }

    function createPToken(address _admin, address _underlying) internal returns (PToken) {
        PToken pToken = new PToken("Protected Token", "PTOKEN", _underlying);
        pToken.transferOwnership(_admin);
        return pToken;
    }

    function createDefaultIRM() internal returns (TripleSlopeRateModel) {
        uint256 baseRatePerSecond = 0.000000001e18;
        uint256 borrowPerSecond1 = 0.000000001e18;
        uint256 kink1 = 0.8e18;
        uint256 borrowPerSecond2 = 0.000000001e18;
        uint256 kink2 = 0.9e18;
        uint256 borrowPerSecond3 = 0.000000001e18;

        return new TripleSlopeRateModel(
            baseRatePerSecond,
            borrowPerSecond1,
            kink1,
            borrowPerSecond2,
            kink2,
            borrowPerSecond3
        );
    }

    function createIRM(
        uint256 baseRatePerSecond,
        uint256 borrowPerSecond1,
        uint256 kink1,
        uint256 borrowPerSecond2,
        uint256 kink2,
        uint256 borrowPerSecond3
    ) internal returns (TripleSlopeRateModel) {
        return new TripleSlopeRateModel(
            baseRatePerSecond,
            borrowPerSecond1,
            kink1,
            borrowPerSecond2,
            kink2,
            borrowPerSecond3
        );
    }

    function createRegistry() internal returns (FeedRegistry) {
        return new FeedRegistry();
    }

    function createPriceOracle(address _admin, address _registry) internal returns (PriceOracle) {
        PriceOracle oracle = new PriceOracle(_registry, address(0), address(0));
        oracle.transferOwnership(_admin);
        vm.prank(_admin);
        oracle.acceptOwnership();
        return oracle;
    }

    function createPriceOracle(address _admin, address _registry, address _steth, address _wsteth)
        internal
        returns (PriceOracle)
    {
        PriceOracle oracle = new PriceOracle(_registry, _steth, _wsteth);
        oracle.transferOwnership(_admin);
        vm.prank(_admin);
        oracle.acceptOwnership();
        return oracle;
    }

    function createAndListERC20Market(
        uint8 _underlyingDecimals,
        address _admin,
        IronBank _ironBank,
        MarketConfigurator _configurator,
        TripleSlopeRateModel _irm,
        uint16 _reserveFactor
    ) internal returns (ERC20Market, IBToken, DebtToken) {
        ERC20Market market = new ERC20Market("Token", "TOKEN", _underlyingDecimals, _admin);
        IBToken ibToken = createIBToken(_admin, address(_ironBank), address(market));
        DebtToken debtToken = createDebtToken(_admin, address(_ironBank), address(market));

        vm.prank(_admin);
        _configurator.listMarket(address(market), address(ibToken), address(debtToken), address(_irm), _reserveFactor);
        return (market, ibToken, debtToken);
    }

    function createAndListERC20Market(
        address _market,
        address _admin,
        IronBank _ironBank,
        MarketConfigurator _configurator,
        TripleSlopeRateModel _irm,
        uint16 _reserveFactor
    ) internal returns (IBToken, DebtToken) {
        IBToken ibToken = createIBToken(_admin, address(_ironBank), _market);
        DebtToken debtToken = createDebtToken(_admin, address(_ironBank), _market);

        vm.prank(_admin);
        _configurator.listMarket(_market, address(ibToken), address(debtToken), address(_irm), _reserveFactor);
        return (ibToken, debtToken);
    }

    function configureMarketAsCollateral(
        address _admin,
        MarketConfigurator _configurator,
        address _market,
        uint16 _collateralFactor
    ) internal {
        uint16 liquidationBonus = 11000; // 110%

        vm.prank(_admin);
        _configurator.configureMarketAsCollateral(_market, _collateralFactor, _collateralFactor, liquidationBonus);
    }

    function setPriceForMarket(
        PriceOracle oracle,
        FeedRegistry registry,
        address admin,
        address market,
        address base,
        address quote,
        int256 price
    ) internal {
        vm.startPrank(admin);
        registry.setAnswer(base, quote, price);
        PriceOracle.Aggregator[] memory aggrs = new PriceOracle.Aggregator[](1);
        aggrs[0] = PriceOracle.Aggregator({asset: market, base: base, quote: quote});
        oracle._setAggregators(aggrs);
        vm.stopPrank();
    }

    function setPriceForMarket(PriceOracle oracle, address admin, address market, address base, address quote)
        internal
    {
        vm.startPrank(admin);
        PriceOracle.Aggregator[] memory aggrs = new PriceOracle.Aggregator[](1);
        aggrs[0] = PriceOracle.Aggregator({asset: market, base: base, quote: quote});
        oracle._setAggregators(aggrs);
        vm.stopPrank();
    }

    function setPriceToRegistry(FeedRegistry registry, address admin, address base, address quote, int256 price)
        internal
    {
        vm.startPrank(admin);
        registry.setAnswer(base, quote, price);
        vm.stopPrank();
    }

    function createUniswapExtension(
        address _admin,
        IronBank _ironBank,
        address _uniV3Factory,
        address _uniV2Factory,
        address _weth,
        address _steth,
        address _wsteth
    ) internal returns (UniswapExtension) {
        UniswapExtension ext =
            new UniswapExtension(address(_ironBank), _uniV3Factory, _uniV2Factory, _weth, _steth, _wsteth);
        ext.transferOwnership(_admin);
        vm.startPrank(_admin);
        ext.acceptOwnership();
        vm.stopPrank();
        return ext;
    }

    function createTxBuilderExtension(
        address _admin,
        IronBank _ironBank,
        address _weth,
        address _steth,
        address _wsteth
    ) internal returns (TxBuilderExtension) {
        TxBuilderExtension ext = new TxBuilderExtension(address(_ironBank), _weth, _steth, _wsteth);
        ext.transferOwnership(_admin);
        vm.startPrank(_admin);
        ext.acceptOwnership();
        vm.stopPrank();
        return ext;
    }

    function createLens() internal returns (IronBankLens) {
        return new IronBankLens();
    }

    function createFlashLoan(IronBank _ironBank) internal returns (FlashLoan) {
        return new FlashLoan(address(_ironBank));
    }
}
