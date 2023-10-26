import { writeFileSync, readFileSync, existsSync, mkdir, mkdirSync } from "fs";

const RELEVANT_ABIS = [
  "AllowListGateKeeper",
  "Party",
  "AuctionCrowdfund",
  "RollingAuctionCrowdfund",
  "BuyCrowdfund",
  "CollectionBuyCrowdfund",
  "CollectionBatchBuyCrowdfund",
  "CrowdfundFactory",
  "PartyFactory",
  "PartyGovernance",
  "PartyHelpers",
  "ProposalExecutionEngine",
  "TokenDistributor",
  "TokenGateKeeper",
  "RendererStorage",
  "PartyNFTRenderer",
  "CrowdfundNFTRenderer",
  "InitialETHCrowdfund",
  "ReraiseETHCrowdfund",
  "CollectionBatchBuyOperator",
  "PixeldroidConsoleFont",
  "Globals",
  "ERC20SwapOperator",
  "BasicMetadataProvider",
  "SSTORE2MetadataProvider",
  "MetadataRegistry",
  "AtomicManualParty",
  "ContributionRouter",
  "AddPartyCardsAuthority",
];

// AFileName -> a_file_name
const camelCaseToUnderscoreCase = (camelCaseString: string) => {
  return camelCaseString
    .replace("NFT", "Nft")
    .replace("ERC", "Erc")
    .replace("ETH", "Eth")
    .split(/\.?(?=[A-Z])/)
    .join("_")
    .toLowerCase();
};

const saveAbis = async () => {
  const output: {
    [filename: string]: any;
  } = {};

  RELEVANT_ABIS.forEach(filename => {
    const fileLoc = `./out/${filename}.sol/${filename}.json`;
    if (!existsSync(fileLoc)) {
      console.warn(`${fileLoc} does not exist`);
      return;
    }
    const contents = readFileSync(fileLoc).toString();
    const foundAbi = JSON.parse(contents)["abi"];
    if (!foundAbi) {
      throw new Error(`couldnt find expected abi in ${fileLoc}`);
    }

    const newFilename = camelCaseToUnderscoreCase(filename);
    output[newFilename] = foundAbi;
  });

  // Create the directory if it doesn't exist
  if (!existsSync("./deploy/cache/abis")) mkdirSync("./deploy/cache/abis");

  Object.keys(output).forEach(newFilename => {
    writeFileSync(
      `./deploy/cache/abis/${newFilename}.json`,
      JSON.stringify(output[newFilename], undefined, 2),
    );
  });
};

saveAbis().then(() => {
  process.stdout.write("0x0000000000000000000000000000000000000001");
  process.exit();
});
