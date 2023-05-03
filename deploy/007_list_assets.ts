import { DeployFunction } from "hardhat-deploy/dist/types";

const deployFn: DeployFunction = async (hre) => {};

deployFn.tags = ["ListMarkets", "deploy"];
deployFn.dependencies = ["IronBank", "PriceOracle", "InterestRateModel", "MarketConfigurator"];
export default deployFn;
