import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const deployFn: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, ethers, getNamedAccounts } = hre;
  const { execute, get } = deployments;
  const { defaultAbiCoder, formatBytes32String, parseEther, parseUnits } = ethers.utils;

  const network = hre.network as any;
  if (network.config.forking || network.name !== "hardhat") {
    return;
  }

  const { admin, user1, user2 } = await getNamedAccounts();

  const usdcAddress = (await get("USDC")).address;
  const ironBankAddress = (await get("IronBank")).address;
  const txBuilderExtAddress = (await deployments.get("TxBuilderExtension")).address;

  await execute("WBTC", { from: admin, log: true }, "approve", ironBankAddress, parseUnits("100", 8));
  await execute(
    "IronBank",
    { from: admin, log: true },
    "supply",
    admin,
    admin,
    (
      await get("WBTC")
    ).address,
    parseUnits("100", 8)
  );
  await execute("USDT", { from: admin, log: true }, "approve", ironBankAddress, parseUnits("100000", 6));
  await execute(
    "IronBank",
    { from: admin, log: true },
    "supply",
    admin,
    admin,
    (
      await get("USDT")
    ).address,
    parseUnits("100000", 6)
  );

  await execute("USDC", { from: admin, log: true }, "transfer", user2, parseUnits("500000", 6));
  await execute("USDC", { from: user2, log: true }, "approve", ironBankAddress, parseUnits("500000", 6));
  await execute("IronBank", { from: user2, log: true }, "supply", user2, user2, usdcAddress, parseUnits("500000", 6));

  await execute("StETH", { from: admin, log: true }, "transfer", user1, parseEther("100"));
  await execute("WBTC", { from: admin, log: true }, "transfer", user1, parseUnits("1.57", 8));
  await execute("USDT", { from: admin, log: true }, "transfer", user1, parseUnits("48800", 6));
  await execute("USDC", { from: admin, log: true }, "transfer", user1, parseUnits("10000", 6));
  await execute("WETH", { from: user1, value: parseEther("0.87"), log: true }, "deposit");

  await execute("IronBank", { from: user1, log: true }, "setUserExtension", txBuilderExtAddress, true);
  await execute("TxBuilderExtension", { from: user1, log: true, value: parseEther("10") }, "execute", [
    [formatBytes32String("ACTION_SUPPLY_NATIVE_TOKEN"), defaultAbiCoder.encode(["uint256"], [parseEther("10")])],
    [
      formatBytes32String("ACTION_BORROW"),
      defaultAbiCoder.encode(["address", "uint256"], [usdcAddress, parseUnits("8551", 6)]),
    ],
  ]);

  await network.provider.send("evm_setAutomine", [false]);
  await network.provider.send("evm_setIntervalMining", [3000]);
};

deployFn.dependencies = ["ListMarkets"];
deployFn.tags = ["SetupTestCase"];
export default deployFn;
