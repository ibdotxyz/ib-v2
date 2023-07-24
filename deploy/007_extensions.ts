import { DeployFunction } from "hardhat-deploy/dist/types";

const deployFn: DeployFunction = async (hre) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy, execute, get } = deployments;

  const { admin, deployer } = await getNamedAccounts();

  const ironBankAddress = (await get("IronBank")).address;

  var wethAddress, stETHAddress, wstETHAddress;
  const network = hre.network as any;
  if (network.config.forking || network.name == "mainnet" || network.name == "goerli") {
    const { weth, stETH, wstETH, uniswapV3Factory, uniswapV2Factory } = await getNamedAccounts();
    wethAddress = weth;
    stETHAddress = stETH;
    wstETHAddress = wstETH;

    await deploy("UniswapExtension", {
      from: deployer,
      args: [ironBankAddress, uniswapV3Factory, uniswapV2Factory, wethAddress, stETHAddress, wstETHAddress],
      log: true,
    });
    await execute("UniswapExtension", { from: deployer, log: true }, "transferOwnership", admin);
  } else {
    await deploy("Multicall2", {
      from: deployer,
      args: [],
      log: true,
    });

    const wethContract = await deploy("WETH", {
      from: deployer,
      contract: "WETH",
      args: [],
      log: true,
    });
    wethAddress = wethContract.address;
    stETHAddress = (await get("StETH")).address;
    wstETHAddress = (await get("WstETH")).address;

    // TODO: Mock UniswapExtension
  }

  await deploy("TxBuilderExtension", {
    from: deployer,
    args: [ironBankAddress, wethAddress, stETHAddress, wstETHAddress],
    log: true,
  });

  await execute("TxBuilderExtension", { from: deployer, log: true }, "transferOwnership", admin);
};

deployFn.tags = ["Extension", "deploy"];
export default deployFn;
