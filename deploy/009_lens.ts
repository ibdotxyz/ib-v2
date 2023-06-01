import { DeployFunction } from "hardhat-deploy/dist/types";

const deployFn: DeployFunction = async (hre) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  await deploy("IronBankLens", {
    from: deployer,
    args: [],
    log: true,
  });
};

deployFn.tags = ["Lens", "deploy"];
export default deployFn;
