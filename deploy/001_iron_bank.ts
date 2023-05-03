import { DeployFunction } from "hardhat-deploy/dist/types";

const deployFn: DeployFunction = async (hre) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();

  await deploy("IronBankImplementation", {
    from: deployer,
    contract: "IronBank",
    log: true,
  });
};

deployFn.tags = ["IronBank", "IBImplementation", "implementation"];

export default deployFn;
