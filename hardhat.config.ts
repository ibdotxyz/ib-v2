import "dotenv/config";
import { HardhatUserConfig } from "hardhat/types";
import "hardhat-deploy";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "@nomicfoundation/hardhat-foundry";

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  solidity: {
    compilers: [
      {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: true,
          },
        },
      },
    ],
  },
  paths: {
    sources: "./src",
  },
  namedAccounts: {
    deployer: 0,
    admin: {
      default: 0,
      mainnet: "0xA5fC0BbfcD05827ed582869b7254b6f141BA84Eb",
    },
    wrappedNative: {
      avalanche: "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7",
      op: "0x4200000000000000000000000000000000000006",
      kovOp: "0x4200000000000000000000000000000000000006",
    },
    registry: {
      default: "0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf",
    },
  },
  networks: {
    hardhat: {
      forking: {
        url: `https://mainnet.infura.io/v3/${process.env.INFURA_TOKEN}`,
      },
    },
    mainnet: {
      url: `https://mainnet.infura.io/v3/${process.env.INFURA_TOKEN}`,
      accounts: [`0x${process.env.DEPLOY_PRIVATE_KEY ?? ""}`],
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      accounts: ["0x0c111f34151faefcbc215a9b78cf2f6a3f39f649f19b34e42862628cb8f95b00"],
    },
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY ?? "",
      avalanche: process.env.SNOWSCAN_API_KEY ?? "",
      opera: process.env.FTMSCAN_API_KEY ?? "",
      optimisticEthereum: process.env.OPSCAN_API_KEY ?? "",
    },
  },
};

export default config;
