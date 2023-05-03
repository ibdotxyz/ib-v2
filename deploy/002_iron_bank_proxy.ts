import { DeployFunction } from "hardhat-deploy/dist/types";

const deployFn: DeployFunction = async (hre) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy, execute, get, save } = deployments;

  const { deployer, admin } = await getNamedAccounts();

  const ironBankImplementation = await get("IronBankImplementation");

  const ironBankProxy = await deploy("IronBankProxy", {
    from: deployer,
    contract: "IronBankProxy",
    args: [ironBankImplementation.address, "0x"],
    log: true,
  });

  // save IronBank deployment with proxy address and implementation abi
  await save("IronBank", {
    abi: ironBankImplementation.abi,
    address: ironBankProxy.address,
  });

  await execute("IronBank", { from: deployer, log: true }, "initialize", admin);
};

deployFn.tags = ["IronBank", "Proxy", "deploy"];
deployFn.dependencies = ["IBImplementation"];
export default deployFn;
