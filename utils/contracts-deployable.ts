import childProcess from "child_process";

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
  const buildArgs = process.argv.slice(2).join(" ");
  await run(`forge build ${buildArgs} --sizes`);
}

main();
