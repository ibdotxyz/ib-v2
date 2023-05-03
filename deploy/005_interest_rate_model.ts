import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const deployFn: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const parseEther = hre.ethers.utils.parseEther;

  const { deployer } = await getNamedAccounts();

  let baseRate = 0;
  let slope1 = parseEther("0.15");
  let kink1 = parseEther("0.8");
  let slope2 = parseEther("0");
  let kink2 = parseEther("0.9");
  let slope3 = parseEther("5");
  await deploy("MajorIRM", {
    from: deployer,
    contract: "TripleSlopeRateModel",
    args: [baseRate, slope1, kink1, slope2, kink2, slope3],
    log: true,
  });

  slope1 = parseEther("0.18");
  slope3 = parseEther("8");
  await deploy("StableIRM", {
    from: deployer,
    contract: "TripleSlopeRateModel",
    args: [baseRate, slope1, kink1, slope2, kink2, slope3],
    log: true,
  });

  slope1 = parseEther("0.2");
  kink1 = parseEther("0.7");
  kink2 = parseEther("0.8");
  slope3 = parseEther("5");
  await deploy("GovIRM", {
    from: deployer,
    contract: "TripleSlopeRateModel",
    args: [baseRate, slope1, kink1, slope2, kink2, slope3],
    log: true,
  });
};
deployFn.tags = ["InterestRateModel"];
export default deployFn;
