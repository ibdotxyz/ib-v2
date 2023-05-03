import { DeployFunction } from "hardhat-deploy/dist/types";

const deployFn: DeployFunction = async (hre) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy, execute, get } = deployments;

  const { deployer, admin } = await getNamedAccounts();

  const ironBank = await get("IronBank");

  const creditLimitManager = await deploy("CreditLimitManager", {
    from: deployer,
    args: [ironBank.address],
    log: true,
  });

  await execute("IronBank", { from: deployer, log: true }, "setCreditLimitManager", creditLimitManager.address);
  await execute("CreditLimitManager", { from: deployer, log: true }, "transferOwnership", admin);
};

deployFn.tags = ["creditLimitManager", "deploy"];
deployFn.dependencies = ["IronBank"];
export default deployFn;
