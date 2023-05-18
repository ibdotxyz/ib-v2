import { DeployFunction } from "hardhat-deploy/dist/types";

const deployFn: DeployFunction = async (hre) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy, execute, get } = deployments;

  const { deployer, admin } = await getNamedAccounts();

  var registryAddress, stETHAddress, wstETHAddress;

  const network = hre.network as any;
  if (network.config.forking || network.name == "mainnet") {
    const { registry, stETH, wstETH } = await getNamedAccounts();
    registryAddress = registry;
    stETHAddress = stETH;
    wstETHAddress = wstETH;
  } else {
    const registry = await deploy("MockFeedRegistry", {
      from: deployer,
      args: [],
      log: true,
    });
    registryAddress = registry.address;

    const stETH = await deploy("StETH", {
      from: deployer,
      contract: "MockERC20",
      args: ["staked Ether 2.0", "stETH", 18, deployer],
      log: true,
    });
    stETHAddress = stETH.address;

    const wstETH = await deploy("WstETH", {
      from: deployer,
      contract: "MockWstEth",
      args: ["Wrapped liquid staked Ether 2.0", "wstETH", stETHAddress, "1124504367992424664"],
      log: true,
    });
    wstETHAddress = wstETH.address;
  }

  const priceOracle = await deploy("PriceOracle", {
    from: deployer,
    args: [registryAddress, stETHAddress, wstETHAddress],
    log: true,
  });

  await execute("IronBank", { from: deployer, log: true }, "setPriceOracle", priceOracle.address);
  await execute("PriceOracle", { from: deployer, log: true }, "transferOwnership", admin);
};

deployFn.tags = ["PriceOracle", "deploy"];
export default deployFn;
