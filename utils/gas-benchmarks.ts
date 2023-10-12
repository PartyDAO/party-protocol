import childProcess from "child_process";
import fs from "fs";

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
  childProcess.exec("forge test --match-contract GasBenchmarks -vv", (error, stdout, stderr) => {
    const outputLines = stdout.split("\n");
    let wantedOutput = new Array<string>();
    wantedOutput.push("Gas Report:");
    for (let i = 0; i < outputLines.length; i++) {
      const outputLine = outputLines[i].trim();
      if (
        outputLine.startsWith("Logs") ||
        outputLine.includes("[PASS]") ||
        outputLine == "" ||
        outputLine.startsWith("Test result:") ||
        outputLine.startsWith("Ran 1 test") ||
        outputLine.endsWith("test/GasBenchmarks.t.sol:GasBenchmarks") ||
        outputLine.startsWith("No files changed")
      ) {
        continue;
      }
      wantedOutput.push(outputLine);
    }
    fs.writeFileSync("gas-results.txt", wantedOutput.join("\n"));
  });
}

main();
