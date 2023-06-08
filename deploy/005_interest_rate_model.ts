import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const deployFn: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const parseEther = hre.ethers.utils.parseEther;

  const { deployer } = await getNamedAccounts();

  const secondsPerYear = 365 * 24 * 60 * 60;

  let baseRate = 0;
  let slope1 = parseEther("0.15").div(secondsPerYear);
  let kink1 = parseEther("0.8").div(secondsPerYear);
  let slope2 = parseEther("0");
  let kink2 = parseEther("0.9").div(secondsPerYear);
  let slope3 = parseEther("5").div(secondsPerYear);
  await deploy("MajorIRM", {
    from: deployer,
    contract: "TripleSlopeRateModel",
    args: [baseRate, slope1, kink1, slope2, kink2, slope3],
    log: true,
  });

  slope1 = parseEther("0.18").div(secondsPerYear);
  slope3 = parseEther("8").div(secondsPerYear);
  await deploy("StableIRM", {
    from: deployer,
    contract: "TripleSlopeRateModel",
    args: [baseRate, slope1, kink1, slope2, kink2, slope3],
    log: true,
  });

  slope1 = parseEther("0.2").div(secondsPerYear);
  kink1 = parseEther("0.7").div(secondsPerYear);
  kink2 = parseEther("0.8").div(secondsPerYear);
  slope3 = parseEther("5").div(secondsPerYear);
  await deploy("GovIRM", {
    from: deployer,
    contract: "TripleSlopeRateModel",
    args: [baseRate, slope1, kink1, slope2, kink2, slope3],
    log: true,
  });
};
deployFn.tags = ["InterestRateModel"];
export default deployFn;
