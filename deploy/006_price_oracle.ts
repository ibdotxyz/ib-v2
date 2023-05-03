import { DeployFunction } from "hardhat-deploy/dist/types";

const deployFn: DeployFunction = async (hre) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy, execute, get } = deployments;

  const { deployer, admin } = await getNamedAccounts();

  var registryAddress;
  const network = hre.network as any;
  if (network.config.forking || network.name == "mainnet") {
    const { registry } = await getNamedAccounts();
    registryAddress = registry;
  } else {
    const registry = await deploy("FeedRegistry", {
      from: deployer,
      args: [],
      log: true,
    });
    registryAddress = registry.address;
  }

  const priceOracle = await deploy("PriceOracle", {
    from: deployer,
    args: [registryAddress],
    log: true,
  });

  await execute("IronBank", { from: deployer, log: true }, "setPriceOracle", priceOracle.address);
  await execute("PriceOracle", { from: deployer, log: true }, "transferOwnership", admin);
};

deployFn.tags = ["PriceOracle", "deploy"];
export default deployFn;
