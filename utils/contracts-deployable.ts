import childProcess from "child_process";
import fs from "fs";
import { glob } from "glob";

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

async function main() {
  await run("rm -rf out/");
  await run("rm -rf test/");
  await run("rm -rf deploy/");
  await run("forge build --optimize --optimizer-runs 200");
  const files = await glob("out/**/*.json");
  for (const file of files) {
    checkContractSize(file);
  }
}

function checkContractSize(contractFile: string) {
  const fileContents = JSON.parse(fs.readFileSync(contractFile, "utf8"));
  if (
    !fileContents.deployedBytecode.hasOwnProperty("object") ||
    fileContents.deployedBytecode.object == "0x"
  ) {
    return true;
  }
  const deployedBytecodeSize = (fileContents.deployedBytecode.object.length - 2) / 2;
  if (deployedBytecodeSize > 24576) {
    throw new Error(
      `Contract ${contractFile} is too large to deploy. ${deployedBytecodeSize} bytes`,
    );
  }
  console.log(
    `Contract ${
      contractFile.split("/").at(-1).split(".")[0]
    } is deployable. Size: ${deployedBytecodeSize} bytes`,
  );
}

main();
