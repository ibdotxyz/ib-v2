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
    user1: 1,
    user2: 2,
    admin: {
      mainnet: "0xA5fC0BbfcD05827ed582869b7254b6f141BA84Eb",
      default: 0,
    },
    registry: {
      default: "0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf",
    },
    weth: {
      default: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    },
    stETH: {
      default: "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84",
    },
    wstETH: {
      default: "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0",
    },
    uniswapV3Factory: {
      default: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
    },
    uniswapV2Factory: {
      default: "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f",
    },
  },
  networks: {
    hardhat: {
      // forking: {
      //   url: `https://mainnet.infura.io/v3/${process.env.INFURA_TOKEN}`,
      // },
    },
    mainnet: {
      url: `https://mainnet.infura.io/v3/${process.env.INFURA_TOKEN}`,
      accounts: [`0x${process.env.DEPLOY_PRIVATE_KEY ?? ""}`],
    },
    localhost: {
      url: "http://127.0.0.1:8545",
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
