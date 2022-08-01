import { writeFileSync } from "fs";

const outputFile = () => {
  const args = process.argv.slice(2);
  if (args.length !== 2) {
    throw new Error(`Please specify two arguments to output file script`);
  }
  const [filename, fileContent] = args;
  const filePath = `./deploy/deployed-contracts/${filename}.json`;

  const parsedContent = JSON.parse(fileContent);
  const niceDisplay = JSON.stringify(parsedContent, undefined, 2);

  writeFileSync(filePath, niceDisplay);
};

outputFile();

// for response
process.stdout.write("0x0000000000000000000000000000000000000001");
