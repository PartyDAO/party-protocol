import * as fs from "fs";
import * as path from "path";
import * as child_process from "child_process";
import * as ethers from "ethers";
import axios from "axios";
import { camelCase } from "change-case";

export const getBlockExplorerApiEndpoint = (chain: string) => {
  if (chain === "mainnet") {
    return "https://api.etherscan.io/api";
  } else if (chain === "base") {
    return "https://api.basescan.org/api";
  } else if (chain === "zora") {
    return "https://api.routescan.io/v2/network/mainnet/evm/7777777/etherscan/api";
  } else if (chain === "base-sepolia") {
    return "https://api-sepolia.basescan.org/api";
  } else {
    return `https://api-${chain}.etherscan.io/api`;
  }
};

export function getBlockExporerApiKey(chain: string) {
  if (chain.startsWith("base")) {
    return process.env.BASESCAN_API_KEY;
  }
  if (chain === "zora") {
    return null;
  }
  return process.env.ETHERSCAN_API_KEY;
}

const readJsonFile = (filePath: string) => {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
};

const getConstructorArgs = (args: any[]) => {
  if (!args) {
    return "";
  }

  return args.join(" ");
};

const getEncodedConstructorArgs = (args: any[], types: string[]) => {
  if (!args || !types) {
    return "";
  }

  const constructorArgs = [];
  for (let i = 0; i < args.length; i++) {
    let arg = args[i];
    const type = types[i];
    if (type.startsWith("uint")) {
      // Format uint types
      arg = parseInt(arg.match(/\d+/)[0]);
    } else if (type.includes("[]")) {
      // Handle array types
      if (arg !== "[]") {
        arg = arg.slice(1, -1).split(", ");
      } else {
        arg = [];
      }
    } else if (type === "string") {
      // Remove quotes from start and end of string (if present)
      arg = arg.replace(/^['"](.*)['"]$/, "$1");
    }

    constructorArgs.push(arg);
  }

  return ethers.AbiCoder.defaultAbiCoder().encode(types, constructorArgs);
};

const generateStandardJson = (
  chain: string,
  contractName: string,
  contractAddress: string,
  constructorArgsEncoded: string,
  optimizerRuns: number,
  compilerVersion: string,
  evmVersion: string,
  libraries: string[],
) => {
  let cmd = `forge verify-contract ${contractAddress} ${contractName} --chain-id ${getChainId(
    chain,
  )} --optimizer-runs ${optimizerRuns} --constructor-args '${constructorArgsEncoded}' --compiler-version ${compilerVersion}`;

  if (chain === "zora") {
    cmd += " --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/7777777/etherscan'";
  }

  if (libraries.length > 0) {
    cmd += ` --libraries ${libraries.join(" ")}`;
  }

  cmd += "  --show-standard-json-input";

  const result = child_process.execSync(cmd).toString();
  const jsonData = JSON.parse(result);
  jsonData["settings"]["viaIR"] = true;
  jsonData["settings"]["evmVersion"] = evmVersion;

  return JSON.stringify(jsonData);
};

const extractVersion = (versionString: string) => {
  const versionMatch = versionString.match(/(\d+\.\d+\.\d+)/);
  return versionMatch[1].split(".").map(Number);
};

const getHighestCompilerVersion = () => {
  const cacheData = readJsonFile(`cache/solidity-files-cache.json`);

  let highestVersion = [0, 0, 0];
  let highestVersionString = "";

  for (const contractData of Object.values(cacheData["files"])) {
    const artifacts = Object.values(contractData as any).pop();
    for (const artifactData of Object.values(artifacts)) {
      for (const versionString of Object.keys(artifactData)) {
        const version = extractVersion(versionString);
        if (version > highestVersion) {
          highestVersionString = versionString;
        }
      }
    }
  }

  return highestVersionString.replace(/\.Darwin\.appleclang/, "");
};

const uploadToBlockExplorer = async (
  chain: string,
  jsonData: string,
  contractName: string,
  contractFilePath: string,
  contractAddress: string,
  optimizerRuns: number,
  constructorArgsEncoded: string,
  evmVersion: string,
  apiKey: string,
) => {
  // Remove 0x at the beginning of the encoded constructor args, if present. Etherscan doesn't like it.
  if (constructorArgsEncoded.startsWith("0x")) {
    constructorArgsEncoded = constructorArgsEncoded.slice(2);
  }

  const response = await axios.post(
    getBlockExplorerApiEndpoint(chain),
    {
      apikey: apiKey,
      module: "contract",
      action: "verifysourcecode",
      contractaddress: contractAddress,
      sourceCode: jsonData,
      codeformat: "solidity-standard-json-input",
      contractname: `${contractFilePath}:${contractName}`,
      compilerversion: `v${getHighestCompilerVersion()}`,
      optimizationUsed: optimizerRuns > 0 ? 1 : 0,
      runs: optimizerRuns,
      constructorArguements: constructorArgsEncoded,
      evmversion: evmVersion,
    },
    {
      headers: {
        "content-type": "application/x-www-form-urlencoded",
      },
    },
  );

  return response.data;
};

const getContractTypes = (contractName: string) => {
  const contractData: any = readJsonFile(`out/${contractName}.sol/${contractName}.json`);

  const constructorData = contractData["abi"].find((elem: any) => elem["type"] === "constructor");

  if (constructorData === undefined) {
    return [];
  } else {
    return constructorData["inputs"].map((inputData: any) => inputData["type"]);
  }
};

const getContractVersion = (contractName: string) => {
  const contractData: any = readJsonFile(`out/${contractName}.sol/${contractName}.json`);

  return contractData["metadata"]["compiler"]["version"];
};

const findLargestNumberedFolder = (chain: string) => {
  const dirPath = `broadcast/${camelCase(chain)}.s.sol`;
  const folders = fs.readdirSync(dirPath).filter(folder => {
    return fs.statSync(path.join(dirPath, folder)).isDirectory() && /^\d+$/.test(folder);
  });
  return Math.max(...folders.map(Number));
};

const getContractNames = (chain: string, libraries: string[]) => {
  const filePath = `deploy/cache/${chain}.json`;

  const deployedContracts = readJsonFile(filePath);

  let contractNames = Object.keys(deployedContracts);

  if (libraries.length > 0) {
    // Extract library names (e.g. "LibRenderer" from "contracts/utils/LibRenderer.sol:LibRenderer:[address]")
    const libraryNames = libraries.map(library => library.split(":")[1]);

    // Include library names in contract names
    contractNames = contractNames.concat(libraryNames);
  }

  return contractNames;
};

const getChainId = (chain: string) => {
  if (chain === "mainnet") {
    return 1;
  } else if (chain === "base") {
    return 8453;
  } else if (chain === "zora") {
    return 7777777;
  } else if (chain === "sepolia") {
    return 11155111;
  } else if (chain === "base-sepolia") {
    return 84532;
  } else {
    throw new Error(`Unknown chain ID for "${chain}". Please add to getChainId() function.`);
  }
};

export const verify = async (chain: string, skip: boolean) => {
  if (!skip) {
    console.log();
    console.log("Waiting before submitting verification requests...");

    await new Promise(resolve => setTimeout(resolve, 15000));
  }

  const largestNumberedFolder = findLargestNumberedFolder(chain);
  const runLatestPath = `broadcast/${camelCase(
    chain,
  )}.s.sol/${largestNumberedFolder}/run-latest.json`;
  const runLatestData = readJsonFile(runLatestPath);

  const cacheData = readJsonFile(`cache/solidity-files-cache.json`);

  const createdContracts = runLatestData["transactions"].filter(
    (transaction: any) => transaction["transactionType"] === "CREATE",
  );

  const apiKey = getBlockExporerApiKey(chain);

  const contractNames = getContractNames(chain, runLatestData["libraries"]);

  const contractTypes: any = {};
  for (const contractName of contractNames) {
    contractTypes[contractName] = getContractTypes(contractName);
  }

  const verificationResults = [];
  for (const contract of createdContracts) {
    const contractName = contract["contractName"];
    if (!contractNames.includes(contractName)) {
      continue;
    }

    const contractFilePath = Object.keys(cacheData["files"]).find(filePath => {
      return cacheData["files"][filePath]["sourceName"].endsWith(`/${contractName}.sol`);
    });

    const contractAddress = contract["contractAddress"];
    const constructorArgsEncoded = getEncodedConstructorArgs(
      contract["arguments"],
      contractTypes[contractName],
    );

    const optimizerRuns =
      cacheData["files"][contractFilePath]["solcConfig"]["settings"]["optimizer"]["runs"];
    const evmVersion = cacheData["files"][contractFilePath]["solcConfig"]["settings"]["evmVersion"];

    const jsonData = generateStandardJson(
      chain,
      contractName,
      contractAddress,
      constructorArgsEncoded,
      optimizerRuns,
      getContractVersion(contractName),
      evmVersion,
      runLatestData["libraries"],
    );

    const response = await uploadToBlockExplorer(
      chain,
      jsonData,
      contractName,
      contractFilePath,
      contractAddress,
      optimizerRuns,
      constructorArgsEncoded,
      evmVersion,
      apiKey,
    );
    console.log(`${contractName}: ${JSON.stringify(response)}`);

    if (response["message"] === "OK") {
      verificationResults.push({
        contract_name: contractName,
        guid: response["result"],
      });
    } else {
      console.error(`Failed to verify ${contractName}`);
    }
  }

  if (verificationResults.length > 0) {
    if (chain === "zora") {
      return; // current explorer not compatible with `verify-check`
    }
    const timeToWait = Math.max(20 * verificationResults.length, 20);

    console.log();
    console.log(`Waiting ${timeToWait} seconds before checking verification results...`);

    await new Promise(resolve => setTimeout(resolve, timeToWait * 1000));

    for (const result of verificationResults) {
      const contractName = result["contract_name"];
      const guid = result["guid"];

      let cmd = `forge verify-check ${guid} --chain-id ${getChainId(chain)}`;
      if (apiKey) {
        cmd += ` --etherscan-api-key ${apiKey}`;
      }

      console.log();
      console.log(`Checking verification result for ${contractName}...`);
      child_process.execSync(cmd);
    }
  }
};
