import { DeployFunction } from "hardhat-deploy/dist/types";

const deployFn: DeployFunction = async (hre) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy, execute, get } = deployments;

  const { deployer, admin } = await getNamedAccounts();

  var registryAddress, stETHAddress, wstETHAddress;

  var priceOracle;

  const network = hre.network as any;
  if (network.config.forking || network.name == "mainnet") {
    const { registry, stETH, wstETH } = await getNamedAccounts();
    registryAddress = registry;
    stETHAddress = stETH;
    wstETHAddress = wstETH;

    priceOracle = await deploy("PriceOracle", {
      from: deployer,
      args: [registryAddress, stETHAddress, wstETHAddress],
      log: true,
    });
    await execute("PriceOracle", { from: deployer, log: true }, "transferOwnership", admin);
  } else {
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

    priceOracle = await deploy("PriceOracle", {
      from: deployer,
      contract: "MockPriceOracle",
      args: [],
      log: true,
    });
  }

  await execute("IronBank", { from: deployer, log: true }, "setPriceOracle", priceOracle.address);
};

deployFn.tags = ["PriceOracle", "deploy"];
export default deployFn;
