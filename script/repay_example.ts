import { deployments, ethers, getNamedAccounts } from "hardhat";
const { defaultAbiCoder, parseEther, parseUnits, formatBytes32String } = ethers.utils;
const { execute } = deployments;

async function main() {
  const { user1 } = await getNamedAccounts();

  const usdcAddress = (await deployments.get("USDC")).address;
  const ironBankAddress = (await deployments.get("IronBank")).address;

  const repayAmount = parseUnits("1000", 6);
  await execute("USDC", { from: user1, log: true }, "approve", ironBankAddress, repayAmount);
  await execute("IronBank", { from: user1, log: true }, "repay", user1, user1, usdcAddress, repayAmount);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
