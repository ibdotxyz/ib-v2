import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const deployFn: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, ethers, getNamedAccounts } = hre;
  const { execute, get } = deployments;
  const { defaultAbiCoder, formatBytes32String, parseEther, parseUnits } = ethers.utils;

  const network = hre.network as any;
  if (network.config.forking || network.name == "mainnet") {
    return;
  }

  const { admin, user1, user2 } = await getNamedAccounts();

  const usdcAddress = (await get("USDC")).address;
  const ironBankAddress = (await get("IronBank")).address;
  const txBuilderExtAddress = (await deployments.get("TxBuilderExtension")).address;

  await execute("USDC", { from: admin, log: true }, "transfer", user2, parseUnits("500000", 6));
  await execute("USDC", { from: user2, log: true }, "approve", ironBankAddress, parseUnits("500000", 6));
  await execute("IronBank", { from: user2, log: true }, "supply", user2, user2, usdcAddress, parseUnits("500000", 6));

  await execute("IronBank", { from: user1, log: true }, "setUserExtension", txBuilderExtAddress, true);
  await execute("TxBuilderExtension", { from: user1, log: true, value: parseEther("10") }, "execute", [
    [formatBytes32String("ACTION_SUPPLY_NATIVE_TOKEN"), "0x"],
    [
      formatBytes32String("ACTION_BORROW"),
      defaultAbiCoder.encode(["address", "uint256"], [usdcAddress, parseUnits("3000", 6)]),
    ],
  ]);
};

deployFn.dependencies = ["ListMarkets"];
deployFn.tags = ["SetupTestCase"];
export default deployFn;
