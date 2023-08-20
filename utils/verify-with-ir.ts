import * as fs from "fs";
import * as path from "path";
import * as child_process from "child_process";
import * as ethers from "ethers";
import axios from "axios";

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
      arg = parseInt(arg.match(/\d+/)[0]);
    } else if (type.includes("[]")) {
      arg = arg.slice(1, -1).split(", ");
    }

    constructorArgs.push(arg);
  }

  return ethers.AbiCoder.defaultAbiCoder().encode(types, constructorArgs).slice(2);
};

const generateStandardJson = (
  chain: string,
  contractName: string,
  contractAddress: string,
  constructorArgs: string,
  optimizerRuns: number,
  compilerVersion: string,
  libraries: string[],
) => {
  let cmd = `forge verify-contract ${contractAddress} ${contractName} --chain ${chain} --optimizer-runs ${optimizerRuns} --constructor-args '${constructorArgs}' --compiler-version ${compilerVersion}`;

  if (libraries.length > 0) {
    cmd += ` --libraries ${libraries.join(" ")}`;
  }

  cmd += "  --show-standard-json-input";

  const result = child_process.execSync(cmd).toString();
  const jsonData = JSON.parse(result);
  jsonData["settings"]["viaIR"] = true;
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

const uploadToEtherscan = async (
  chain: string,
  jsonData: string,
  contractName: string,
  contractFilePath: string,
  contractAddress: string,
  optimizerRuns: number,
  constructorArgsEncoded: string,
  apiKey: string,
) => {
  let endpoint;
  if (chain === "mainnet") {
    endpoint = "https://api.etherscan.io/api";
  } else if (chain === "goerli") {
    endpoint = `https://api-${chain}.etherscan.io/api`;
  }

  const response = await axios.post(
    endpoint,
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
  const dirPath = `broadcast/${chain.charAt(0).toUpperCase() + chain.slice(1)}.s.sol`;
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

export const verifyWithIr = async (chain: string, skip: boolean) => {
  if (!skip) {
    console.log();
    console.log("Waiting before submitting verification requests...");

    await new Promise(resolve => setTimeout(resolve, 15000));
  }

  const largestNumberedFolder = findLargestNumberedFolder(chain);
  const runLatestPath = `broadcast/${
    chain.charAt(0).toUpperCase() + chain.slice(1)
  }.s.sol/${largestNumberedFolder}/run-latest.json`;
  const runLatestData = readJsonFile(runLatestPath);

  const cacheData = readJsonFile(`cache/solidity-files-cache.json`);

  const createdContracts = runLatestData["transactions"].filter(
    (transaction: any) => transaction["transactionType"] === "CREATE",
  );

  const apiKey = process.env.ETHERSCAN_API_KEY;

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
    const constructorArgs = getConstructorArgs(contract["arguments"]);
    const optimizerRuns =
      cacheData["files"][contractFilePath]["solcConfig"]["settings"]["optimizer"]["runs"];

    const jsonData = generateStandardJson(
      chain,
      contractName,
      contractAddress,
      constructorArgs,
      optimizerRuns,
      getContractVersion(contractName),
      runLatestData["libraries"],
    );
    const constructorArgsEncoded = getEncodedConstructorArgs(
      contract["arguments"],
      contractTypes[contractName],
    );
    const response = await uploadToEtherscan(
      chain,
      jsonData,
      contractName,
      contractFilePath,
      contractAddress,
      optimizerRuns,
      constructorArgsEncoded,
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
    const timeToWait = Math.max(20 * verificationResults.length, 60);

    console.log();
    console.log(`Waiting ${timeToWait} seconds before checking verification results...`);

    await new Promise(resolve => setTimeout(resolve, timeToWait * 1000));

    for (const result of verificationResults) {
      const contractName = result["contract_name"];
      const guid = result["guid"];

      const cmd = `forge verify-check ${guid} --chain ${chain}`;

      console.log();
      console.log(`Checking verification result for ${contractName}...`);
      child_process.execSync(cmd);
    }
  }
};
