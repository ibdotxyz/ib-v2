import { formatUnits } from "ethers/lib/utils";
import { DeployFunction } from "hardhat-deploy/dist/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { parse } from "path";

const deployFn: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, ethers, getNamedAccounts } = hre;
  const { deploy, execute, get, save, read } = deployments;
  const { parseUnits } = ethers.utils;

  const { deployer, admin } = await getNamedAccounts();

  const network = hre.network as any;
  if (network.config.forking || network.name == "mainnet") {
    console.log("Skipping list markets on mainnet");
    return;
  }

  const ironBankAddress = (await get("IronBank")).address;
  const ibTokenImplementation = await get("IBToken");
  const debtTokenImplementation = await get("DebtToken");

  const majorIRMAddress = (await get("MajorIRM")).address;
  const stableIRMAddress = (await get("StableIRM")).address;

  const wethAddress = (await get("WETH")).address;
  const usdc = await deploy("USDC", {
    from: deployer,
    contract: "MockERC20",
    args: ["USD Coin", "USDC", 6, deployer],
    log: true,
  });

  const assetToList = [
    ["WETH", wethAddress, majorIRMAddress, "1800", "0.2", "0.82", "0.9", "1.05"],
    ["USDC", usdc.address, stableIRMAddress, "1", "0.15", "0.86", "0.9", "1.1"],
  ];

  for (const [symbol, underlying, irm, price, rf, cf, lt, lb] of assetToList) {
    const ibToken = await deploy(`ib${symbol}`, {
      from: deployer,
      contract: "ERC1967Proxy",
      args: [ibTokenImplementation.address, "0x"],
      log: true,
    });

    await save(`ib${symbol}`, {
      abi: ibTokenImplementation.abi,
      address: ibToken.address,
    });

    await execute(
      `ib${symbol}`,
      { from: deployer, log: true },
      "initialize",
      `Iron Bank ${symbol}`,
      `ib${symbol}`,
      admin,
      ironBankAddress,
      underlying
    );

    const debtToken = await deploy(`debt${symbol}`, {
      from: deployer,
      contract: "ERC1967Proxy",
      args: [debtTokenImplementation.address, "0x"],
      log: true,
    });

    await save(`debt${symbol}`, {
      abi: debtTokenImplementation.abi,
      address: debtToken.address,
    });

    await execute(
      `debt${symbol}`,
      { from: deployer, log: true },
      "initialize",
      `Iron Bank Debt ${symbol}`,
      `debt${symbol}`,
      admin,
      ironBankAddress,
      underlying
    );

    await execute(
      "MarketConfigurator",
      { from: deployer, log: true },
      "listMarket",
      underlying,
      ibToken.address,
      debtToken.address,
      irm,
      parseUnits(rf, 4)
    );

    await execute("PriceOracle", { from: deployer, log: true }, "setPrice", underlying, parseUnits(price, 18));
    await execute(
      "MarketConfigurator",
      { from: deployer, log: true },
      "configureMarketAsCollateral",
      underlying,
      parseUnits(cf, 4),
      parseUnits(lt, 4),
      parseUnits(lb, 4)
    );
  }
};

deployFn.tags = ["ListMarkets", "deploy"];
deployFn.dependencies = [
  "IronBank",
  "PriceOracle",
  "InterestRateModel",
  "MarketConfigurator",
  "Implementation",
  "Extension",
];
export default deployFn;
