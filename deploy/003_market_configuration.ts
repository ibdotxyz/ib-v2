import { DeployFunction } from "hardhat-deploy/dist/types";

const deployFn: DeployFunction = async (hre) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy, execute, get } = deployments;

  const { deployer, admin } = await getNamedAccounts();

  const ironBank = await get("IronBank");

  const marketConfigurator = await deploy("MarketConfigurator", {
    from: deployer,
    args: [ironBank.address],
    log: true,
  });

  await execute("IronBank", { from: deployer, log: true }, "setMarketConfigurator", marketConfigurator.address);
  await execute("MarketConfigurator", { from: deployer, log: true }, "transferOwnership", admin);
};

deployFn.tags = ["marketConfig", "deploy"];
deployFn.dependencies = ["IronBank"];
export default deployFn;
