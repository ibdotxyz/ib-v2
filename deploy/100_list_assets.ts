import { DeployFunction } from "hardhat-deploy/dist/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ethers } from "hardhat";

async function getDecimal(deployResult: any): Promise<number> {
  const contract = await ethers.getContractAt("MockERC20", deployResult.address);
  const decimal = await contract.decimals();
  return decimal;
}

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

  const weth = await get("WETH");
  const wstETH = await get("WstETH");
  const wbtc = await deploy("WBTC", {
    from: deployer,
    contract: "MockERC20",
    args: ["Wrapped BTC", "WBTC", 8, deployer],
    log: true,
  });
  const usdc = await deploy("USDC", {
    from: deployer,
    contract: "MockERC20",
    args: ["USD Coin", "USDC", 6, deployer],
    log: true,
  });
  const usdt = await deploy("USDT", {
    from: deployer,
    contract: "MockERC20",
    args: ["Tether USD", "USDT", 6, deployer],
    log: true,
  });

  const pWETH = await deploy("pWETH", {
    from: deployer,
    contract: "PToken",
    args: ["Protected WETH", "pWETH", weth.address],
    log: true,
  });

  const pUSDC = await deploy("pUSDC", {
    from: deployer,
    contract: "PToken",
    args: ["Protected USDC", "pUSDC", usdc.address],
    log: true,
  });

  const assetToList: any = [
    ["WETH", weth, majorIRMAddress, "1899", "0.2", "0.82", "0.9", "1.05"],
    ["WSTETH", wstETH, majorIRMAddress, "2141", "0.2", "0.8", "0.9", "1.1"],
    ["WBTC", wbtc, majorIRMAddress, "27892", "0.2", "0.75", "0.85", "1.05"],
    ["USDC", usdc, stableIRMAddress, "1", "0.15", "0.86", "0.9", "1.08"],
    ["USDT", usdt, stableIRMAddress, "1", "0.15", "0.86", "0.9", "1.08"],
    ["PWETH", pWETH, majorIRMAddress, "1899", "0.2", "0.82", "0.9", "1.05"],
    ["PUSDC", pUSDC, stableIRMAddress, "1", "0.15", "0.86", "0.9", "1.08"],
  ];

  const marketPTokens = [
    [weth.address, pWETH.address],
    [usdc.address, pUSDC.address],
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
      underlying.address
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
      underlying.address
    );

    await execute(
      "MarketConfigurator",
      { from: deployer, log: true },
      "listMarket",
      underlying.address,
      ibToken.address,
      debtToken.address,
      irm,
      parseUnits(rf, 4)
    );

    await execute(
      "PriceOracle",
      { from: deployer, log: true },
      "setPrice",
      underlying.address,
      parseUnits(price, 18 + 18 - (await getDecimal(underlying)))
    );
    await execute(
      "MarketConfigurator",
      { from: deployer, log: true },
      "configureMarketAsCollateral",
      underlying.address,
      parseUnits(cf, 4),
      parseUnits(lt, 4),
      parseUnits(lb, 4)
    );
  }

  for (const [underlying, pToken] of marketPTokens) {
    await execute("MarketConfigurator", { from: deployer, log: true }, "setMarketPToken", underlying, pToken);
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