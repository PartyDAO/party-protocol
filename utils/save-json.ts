import { existsSync, mkdirSync, writeFileSync } from "fs";

const outputFile = () => {
  const args = process.argv.slice(2);
  if (args.length !== 2) {
    throw new Error(`Please specify two arguments to output file script`);
  }
  const [filename, fileContent] = args;
  const filePath = `./deploy/cache/${filename}.json`;

  const parsedContent = JSON.parse(fileContent);
  const niceDisplay = JSON.stringify(parsedContent, undefined, 2);

  // Create the directory if it doesn't exist
  if (!existsSync("./deploy/cache")) mkdirSync("./deploy/cache");

  writeFileSync(filePath, niceDisplay);
};

outputFile();

// for response
process.stdout.write("0x0000000000000000000000000000000000000001");
