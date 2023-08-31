import fs from "fs";

const jsonString = fs.readFileSync("./out/lint-json.json", "utf8");
try {
  JSON.parse(jsonString);
} catch {
  // Invalid json
  process.stdout.write("0x0000000000000000000000000000000000000000000000000000000000000002");
  process.exit();
}

process.stdout.write("0x0000000000000000000000000000000000000000000000000000000000000001");
process.exit();
