import { DeployFunction } from "hardhat-deploy/dist/types";

const deployFn: DeployFunction = async (hre) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  await deploy("IBToken", {
    from: deployer,
    args: [],
    log: true,
  });

  await deploy("DebtToken", {
    from: deployer,
    args: [],
    log: true,
  });
};

deployFn.tags = ["Implementation", "deploy"];
deployFn.dependencies = ["IronBank", "PriceOracle", "InterestRateModel", "MarketConfigurator"];
export default deployFn;
