import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const deployFn: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, ethers, getNamedAccounts, getUnnamedAccounts } = hre;
  const { execute, deploy, get, getArtifact, read, save } = deployments;
  const { parseUnits, formatEther } = ethers.utils;

  const network = hre.network as any;
  if (network.config.forking || network.name == "mainnet") {
    return;
  }

  const { deployer, user1, user2 } = await getNamedAccounts();

  const wethAddress = (await get("WETH")).address;
  const ironBankAddress = (await get("IronBank")).address;

  await execute("WETH", { from: user1, log: true, value: parseUnits("1", 18) }, "deposit");
  await execute("WETH", { from: user1, log: true }, "approve", ironBankAddress, parseUnits("1", 18));
  await execute("IronBank", { from: user1, log: true }, "supply", user1, user1, wethAddress, parseUnits("1", 18));
};

deployFn.dependencies = ["ListMarkets"];
deployFn.tags = ["SetupTestCase"];
export default deployFn;
