import readline from "readline";
import childProcess from "child_process";
import fs from "fs";
import { toChecksumAddress } from "ethereumjs-util";
import "colors";
import path from "path";
import { createHash } from "crypto";
import { snakeCase, camelCase } from "change-case";

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

async function setDeployConstants(chain: string) {
  const currDir = process.cwd();
  const deployPath = `${currDir}/deploy/Deploy.s.sol`;
  const jsonPath = `${currDir}/deploy/deployed-contracts/${chain}.json`;

  // Load the {chain}.json file and parse the JSON data
  const data = JSON.parse(fs.readFileSync(jsonPath, "utf-8"));

  // Read the entire Deploy.s.sol file as a single string
  let content = fs.readFileSync(deployPath, "utf-8");

  // Iterate over the keys and values in the JSON data
  for (const [key, value] of Object.entries(data)) {
    const camelCaseKey = camelCase(key);

    // Use a regex pattern to search for the variable name
    // in the Deploy.s.sol file and replace it with the value
    // from the {chain}.json file, but only replace the
    // first occurrence of the variable name
    const pattern = new RegExp(` ${camelCaseKey}`);
    const match = content.match(new RegExp(`(\\w+)\\s+public\\s+${camelCaseKey};`, "m"));
    if (!match) {
      console.warn(`Skipping ${key}`.yellow);
      continue;
    }

    // Get the type of the variable
    const type = match[1];

    // Use the key and value from the {chain}.json file
    // to construct a new line of code that sets the
    // variable name to the corresponding value
    const replacement = ` ${camelCaseKey} = ${type}(${toChecksumAddress(value as string)})`;
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
  const jsonPath: string = `deploy/deployed-contracts/${chain}.json`;

  // Load the JSON file and parse the data
  const data: any = JSON.parse(await fs.promises.readFile(jsonPath, "utf8"));

  // Open the README.md file for reading
  const content: string[] = (await fs.promises.readFile("README.md", "utf8")).split("\n");

  for (const key in data) {
    if (!content.join("\n").includes(key)) {
      console.log(`${key} not found in README.md deployments`.red);
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
          content[i] = content[i].replace(oldAddress, address);
          content[i] = content[i].replace(oldAddress, address); // Replacing twice to match the `count` parameter in the Bash script

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
  const src = "deploy/deployed-contracts/abis";
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
  const addressesPath = path.join("deploy", "deployed-contracts", `${chain}.json`);
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

      const contractFilePath = path.join("deploy/deployed-contracts/abis", contractFileName);
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
  const deploymentJsonPath = `deploy/deployed-contracts/${chain}.json`;
  const headJsonFile = `lib/party-addresses/contracts/${chain}/head.json`;

  // Get list of all updated contracts from the deployment JSON file keys
  const deploymentData = fs.readFileSync(deploymentJsonPath, "utf8");
  const updated_contracts = Object.keys(JSON.parse(deploymentData));

  // Update only values of updated contracts to the release name in the
  // head JSON file. Leave other values unchanged.
  const headData = fs.readFileSync(headJsonFile, "utf8");
  const head_json = JSON.parse(headData);

  for (const contract of updated_contracts) head_json[contract] = releaseName;

  fs.writeFileSync(headJsonFile, JSON.stringify(head_json, null, 2));
}

// TODO: Add comments explaining each step
async function main() {
  const chain = process.argv[2];

  if (!chain) {
    console.error("Missing chain argument".red);
    process.exit(1);
  }

  await confirm("Are there other changes that could be batched into this deploy?", false);

  if (await confirm("Do you want to set deployment constants to existing addresses?", false)) {
    await setDeployConstants(chain);
  }

  await confirm("Do you need to update deployer addresses?", false);

  if (
    await confirm(
      "Do you want to check that deploy script variable names match contract names?",
      true,
    )
  ) {
    await checkDeployContractVariables();
  }

  await confirm('Have you updated "deploy.sol" to only deploy the contracts you want?', true);

  let dryRunSucceeded = false;
  while (!dryRunSucceeded) {
    if (await confirm("Do dry run?", true)) {
      await run(`yarn deploy:${chain}:dry --private-key ${process.env.PRIVATE_KEY}`);
      await run("yarn lint:fix > /dev/null");
      await checksumAddresses(`deploy/deployed-contracts/${chain}.json`);

      if (await confirm("Did dry run succeed?", true)) {
        dryRunSucceeded = true;
      }
    } else {
      break;
    }

    await confirm(`Does ${chain}.json only contain addresses for contracts that changed?`, true);

    await confirm("Did ABI files change as you expected?", true);
  }

  if (await confirm("Run deploy?", true)) {
    run(`yarn deploy:${chain} --private-key ${process.env.PRIVATE_KEY}`);
    await run("yarn lint:fix > /dev/null");
    await checksumAddresses(`deploy/deployed-contracts/${chain}.json`);

    // TODO: Add way to verify contracts compiled with `via-ir` on Etherscan
    // // Wait for contract code to be uploaded to Etherscan
    // await new Promise(resolve => setTimeout(resolve, 5000));
    // // Do verification stuff ...
  } else {
    process.exit(0);
  }

  if (await confirm("Update addresses in README?", false)) await updateReadmeDeployAddresses(chain);

  run("yarn lint:fix > /dev/null");

  const release_name = await new Promise<string>(resolve =>
    rl.question("What is the release name?", resolve),
  );

  if (await confirm("Copy deploy script to party-addresses?", false)) {
    await copyDeployFile(release_name);
  }

  if (await confirm("Upload ABI files to party-addresses?", true)) await copyABIs();

  if (await confirm("Create release folder in party-addresses?", true)) {
    await createReleaseFolder(chain, release_name);
  }

  if (await confirm("Update head.json in party-addresses?", true)) {
    await updateHeadJson(chain, release_name);
  }

  await run(`prettier --write lib/party-addresses >> /dev/null`);

  if (await confirm("Commit and push changes in party-addresses?", true)) {
    const message = await new Promise<string>(resolve =>
      rl.question("What is the commit message?", resolve),
    );

    await run("cd lib/party-addresses");
    await run("git add .");
    await run(`git commit -m "${message}"`);
    await run("git push origin HEAD:main");
    await run("cd ../..");
  }

  rl.close();
}

main().catch(console.error);
