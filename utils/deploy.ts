import readline from "readline";
import childProcess from "child_process";
import fs from "fs";
import { toChecksumAddress } from "ethereumjs-util";
import path from "path";
import axios from "axios";
import { createHash } from "crypto";
import { snakeCase, camelCase } from "change-case";
import { getEtherscanApiEndpoint, getEtherscanApiKey, verify } from "./verify";
import "colors";

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

async function run(command: string) {
  const result = childProcess.spawnSync(command, [], {
    shell: true,
    stdio: "inherit",
  });

  if (result.status !== 0) {
    throw new Error(`Command "${command}" failed with status code ${result.status}`);
  }

  return result.stdout;
}

async function confirm(question: string, defaultValue?: boolean): Promise<boolean> {
  return new Promise((resolve, reject) => {
    const formattedQuestion =
      defaultValue === undefined ? question : `${question} (${defaultValue ? "Y/n" : "y/N"})`;

    rl.question(formattedQuestion + " ", answer => {
      if (answer.toLowerCase() === "y" || answer.toLowerCase() === "yes") {
        resolve(true);
      } else if (answer.toLowerCase() === "n" || answer.toLowerCase() === "no") {
        resolve(false);
      } else if (defaultValue !== undefined) {
        resolve(defaultValue);
      } else {
        reject("Invalid input");
      }
    });
  });
}

async function checkDeployContractVariables() {
  const currDir = process.cwd();
  const deployFile = `${currDir}/deploy/Deploy.s.sol`;
  const outputAbiFile = `${currDir}/utils/output-abis.ts`;

  // Get all address mapping names in the deploy file
  const deployFileContents = fs.readFileSync(deployFile, "utf-8");
  const addressMappingNames = Array.from(
    deployFileContents.matchAll(/AddressMapping\(\s*"(.+)"/g),
    m => m[1],
  );

  // Get all relevant ABI names in `output-abis.ts`
  const outputAbiFileContents = fs.readFileSync(outputAbiFile, "utf-8");
  const relevantAbiNames = Array.from(outputAbiFileContents.matchAll(/\s{2}"(.+)",/g), m => m[1]);

  // Print all address mapping names that are not in the ABI names
  let noMissingNames = true;
  for (const name of addressMappingNames) {
    if (!relevantAbiNames.includes(name)) {
      noMissingNames = false;
      console.error(`Could not find contract named "${name}" in \`RELEVANT_ABIS\``.red);
    }
  }

  if (noMissingNames) console.log("All good!".green);
}

async function getSourceCode(address: string, chain: string) {
  let tries = 0;
  while (tries < 5) {
    tries++;

    const response = await axios.post(
      getEtherscanApiEndpoint(chain),
      {
        module: "contract",
        action: "getsourcecode",
        address,
        apikey: getEtherscanApiKey(chain),
      },
      {
        headers: {
          "content-type": "application/x-www-form-urlencoded",
        },
      },
    );

    const result = response.data.result;

    if (result != "Max rate limit reached") return result[0];
  }
}

async function setLatestContractAddresses(chain: string) {
  const deployPath = `deploy/Deploy.s.sol`;

  // Load the head.json file in the party-addresses folder
  let head_path = path.join("lib", "party-addresses", "contracts", chain, "head.json");

  // Check if the head.json file exists
  if (!fs.existsSync(head_path)) {
    console.error(`Could not find ${head_path}. Skipping.`.yellow);
  }

  let head_data = JSON.parse(fs.readFileSync(head_path, "utf8"));

  // Create a dictionary to hold the latest addresses for each contract
  let addresses: { [key: string]: string } = {};
  for (let contract in head_data) {
    // Define the path to the release's JSON file
    let release_path = path.join(
      "lib",
      "party-addresses",
      "contracts",
      chain,
      head_data[contract],
      `${contract}.json`,
    );

    // Load the release's JSON file
    let release_data = JSON.parse(fs.readFileSync(release_path, "utf8"));

    // Extract the address and add it to the dictionary
    addresses[contract] = release_data["address"];
  }

  // Read the entire Deploy.s.sol file as a single string
  let content = fs.readFileSync(deployPath, "utf-8");

  // Iterate over the keys and values in the JSON data
  for (const [key, value] of Object.entries(addresses)) {
    let camelCaseKey = camelCase(key)
      // Handle exceptions for contract names
      .replace("Nft", "NFT")
      .replace("Eth", "ETH")
      .replace("Erc", "ERC");

    // Use a regex pattern to search for the variable name
    // in the Deploy.s.sol file and replace it with the value
    // from the {chain}.json file, but only replace the
    // first occurrence of the variable name
    const pattern = new RegExp(` ${camelCaseKey}`);
    const match = content.match(new RegExp(`(\\w+)\\s+public\\s+${camelCaseKey};`, "m"));
    if (!match) {
      console.warn(`Skipping ${key}`.grey);
      continue;
    }

    // Get the type of the variable
    const type = match[1];

    // Convert the address to checksum format
    const address = toChecksumAddress(value as string);

    // Check if the address is for the expected contract
    const sourceCode = await getSourceCode(address, chain);
    const contractName = sourceCode["ContractName"];

    // Handle errors
    if (contractName != key) {
      if (contractName) {
        console.warn(`Expected ${address} to be for ${key}, not ${contractName}. Skipping`.yellow);
      } else if (sourceCode["ABI"] === "Contract source code not verified") {
        console.warn(`Code for ${address} not verified for ${key}. Skipping`.yellow);
      } else {
        console.warn(`Could not confirm ${address} is ${key}. Skipping`.yellow);
      }

      continue;
    }

    // Sets the variable to the corresponding address. Make `payable` to allow
    // compatibility with variables that are expected by compiler to be `address
    // payable`.
    const replacement = ` ${camelCaseKey} = ${type}(payable(${address}))`;

    content = content.replace(pattern, replacement);
  }

  // Write the updated content to the Deploy.s.sol file
  fs.writeFileSync(deployPath, content);
}

async function checksumAddresses(file: string) {
  // Read the contents of the file
  let contents = fs.readFileSync(file, "utf-8");

  // Replace all addresses with their checksum version
  contents = contents.replace(/0x[a-fA-F0-9]{40}/g, match => toChecksumAddress(match));

  // Write the updated contents back to the file
  fs.writeFileSync(file, contents);
}

async function updateReadmeDeployAddresses(chain: string) {
  const jsonPath: string = `deploy/cache/${chain}.json`;

  // Load the JSON file and parse the data
  const data: any = JSON.parse(await fs.promises.readFile(jsonPath, "utf8"));

  // Open the README.md file for reading
  const content: string[] = (await fs.promises.readFile("README.md", "utf8")).split("\n");

  for (const key in data) {
    // Skip if one of these contracts
    if (["PixeldroidConsoleFont", "RendererStorage", "PartyHelpers"].some(name => name === key)) {
      continue;
    }

    if (!content.join("\n").includes(key)) {
      console.log(`${key} not found in README.md deployments`.yellow);
    }
  }

  // Iterate over the keys and values in the JSON data
  for (const [key, value] of Object.entries(data)) {
    const address: string = toChecksumAddress(value as string);

    // Iterate over the lines in the file and find the line that contains the contract name
    for (let i = 0; i < content.length; i++) {
      if (content[i].includes(`\`${key}\``)) {
        const url: string =
          chain === "mainnet"
            ? "https://etherscan.io/address/"
            : `https://${chain}.etherscan.io/address/`;

        const pattern: RegExp = new RegExp(url + "(0x[a-fA-F0-9]{40})");
        const oldAddress: string = content[i].match(pattern)?.[1];

        if (oldAddress) {
          // Replace the address in the line with the address from the JSON data
          content[i] = content[i].replaceAll(oldAddress, address);

          console.log(`Updated ${key} address to ${address}...`);
        }

        break;
      }
    }
  }

  // Open the README.md file for writing
  await fs.promises.writeFile("README.md", content.join("\n"));
}

async function copyDeployFile(releaseName: string): Promise<void> {
  const deployFileContent: string = await fs.promises.readFile("deploy/Deploy.s.sol", "utf8");
  const outputPath: string = path.join("lib/party-addresses/deploy", `${releaseName}.sol`);
  await fs.promises.writeFile(outputPath, deployFileContent);
}

async function copyABIs(): Promise<void> {
  const src = "deploy/cache/abis";
  const dest = "lib/party-addresses/abis";

  for (const filename of await fs.promises.readdir(src)) {
    // Compute the hash of the file contents
    const contents: Buffer = await fs.promises.readFile(path.join(src, filename));
    const hash: string = createHash("sha256").update(contents).digest("hex").slice(0, 8);
    // console.log(`${filename} -> ${hash}.json`);

    // Copy the file to the destination folder
    await fs.promises.writeFile(path.join(dest, `${hash}.json`), contents);
  }
}

async function createReleaseFolder(chain: string, releaseName: string) {
  const addressesPath = path.join("deploy", "cache", `${chain}.json`);
  const addressesData = await fs.promises.readFile(addressesPath, "utf8");
  const addresses = JSON.parse(addressesData);

  const releaseFolder = path.join("lib/party-addresses", "contracts", chain, releaseName);

  // Create the folder if it doesn't exist
  if (!fs.existsSync(releaseFolder)) {
    await fs.promises.mkdir(releaseFolder, { recursive: true });
  }

  for (const [contractName, address] of Object.entries(addresses)) {
    try {
      const contractFileName =
        snakeCase(contractName.replace("NFT", "Nft").replace("ERC", "Erc").replace("ETH", "Eth")) +
        ".json";

      const contractFilePath = path.join("deploy/cache/abis", contractFileName);
      const contractContents = await fs.promises.readFile(contractFilePath);
      const hash = createHash("sha256").update(contractContents).digest("hex").slice(0, 8);

      const contractFile = path.join(releaseFolder, contractName + ".json");
      await fs.promises.writeFile(contractFile, JSON.stringify({ address, abi: hash }, null, 2));
    } catch (error) {
      console.log(`No ABI file found for ${contractName}`.red);
      continue;
    }
  }
}

async function updateHeadJson(chain: string, releaseName: string) {
  const deploymentJsonPath = `deploy/cache/${chain}.json`;
  const headJsonFile = `lib/party-addresses/contracts/${chain}/head.json`;

  // Get list of all updated contracts from the deployment JSON file keys
  const deploymentData = fs.readFileSync(deploymentJsonPath, "utf8");
  const updated_contracts = Object.keys(JSON.parse(deploymentData));

  // Create head JSON file if it doesn't exist
  if (!fs.existsSync(headJsonFile)) fs.writeFileSync(headJsonFile, "{}");

  // Update only values of updated contracts to the release name in the
  // head JSON file. Leave other values unchanged.
  const headData = fs.readFileSync(headJsonFile, "utf8");
  const head_json = JSON.parse(headData);

  for (const contract of updated_contracts) head_json[contract] = releaseName;

  fs.writeFileSync(headJsonFile, JSON.stringify(head_json, null, 2));
}

async function main() {
  const chain = process.argv[2];
  const validChains = ["mainnet", "goerli", "base", "base-goerli"];

  if (!chain) {
    console.error(`Missing chain argument. Valid chains are: ${validChains.join(", ")}`);
    process.exit(1);
  } else if (!validChains.includes(chain)) {
    console.error(`Invalid chain "${chain}". Valid chains are: ${validChains.join(", ")}`);
    process.exit(1);
  }

  if (
    await confirm(
      "Do you want to set contract variables to their existing addresses in Deploy.s.sol?",
      false,
    )
  ) {
    await setLatestContractAddresses(chain);
    // Warn to check that the addresses are correct and to unset variables for
    // contracts that are going to be deployed.
    console.warn("Remember to unset variables for contracts that are going to be deployed!".yellow);
  }

  if (
    await confirm(
      "Do you want to check that deploy script variable names match contract names?",
      true,
    )
  ) {
    await checkDeployContractVariables();
  }

  await confirm("Have you updated Deploy.sol to only deploy the contracts you want?", true);

  let dryRunSucceeded = false;
  while (!dryRunSucceeded) {
    if (await confirm("Do dry run?", true)) {
      await run(`yarn deploy:${chain}:dry --private-key ${process.env.PRIVATE_KEY}`);
      await run("yarn lint:fix > /dev/null");
      await checksumAddresses(`deploy/cache/${chain}.json`);

      if (await confirm("Did dry run succeed?", true)) {
        dryRunSucceeded = true;
      }
    } else {
      break;
    }

    await confirm("Was the deployer the expected address?", true);

    await confirm(
      `Does deploy/cache/${chain}.json only contain addresses for contracts that changed?`,
      true,
    );

    await confirm("Were ABI files in deploy/cache/abis created or changed as you expected?", true);
  }

  await confirm("Are there no other changes that should be included into this deploy?", true);

  if (await confirm("Run deploy?", true)) {
    run(`yarn deploy:${chain} --private-key ${process.env.PRIVATE_KEY}`);
    await run("yarn lint:fix > /dev/null");
    await checksumAddresses(`deploy/cache/${chain}.json`);

    // Wait for contract code to be uploaded to Etherscan
    console.log("Waiting for Etherscan to index contract code...");
    await new Promise(resolve => setTimeout(resolve, 5000));

    await verify(chain, true);
  } else {
    process.exit(0);
  }

  if (await confirm("Update addresses in README?", true)) await updateReadmeDeployAddresses(chain);

  run("yarn lint:fix > /dev/null");

  let release_name;
  while (!release_name) {
    release_name = await new Promise<string>(resolve =>
      rl.question("What is the release name? ", resolve),
    );
  }

  if (await confirm("Copy deploy script to party-addresses?", false)) {
    await copyDeployFile(release_name);
  }

  if (await confirm("Upload ABI files to party-addresses?", true)) await copyABIs();

  if (await confirm("Create or update release folder in party-addresses?", true)) {
    await createReleaseFolder(chain, release_name);
  }

  if (await confirm("Update head.json in party-addresses?", true)) {
    await updateHeadJson(chain, release_name);
  }

  await run(`prettier --write lib/party-addresses >> /dev/null`);

  rl.close();
}

main().catch(console.error);
