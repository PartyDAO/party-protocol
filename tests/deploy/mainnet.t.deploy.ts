import { env as ENV } from "process";
import * as path from "path";
import { expect, use } from "chai";
import { Contract, BigNumber, Wallet } from "ethers";
import { MockProvider, solidity } from "ethereum-waffle";
import * as ethers from "ethers";

import DEPLOY_ARTIFACT from "../../out/deploy.sol/DeployFork.json";
import CF_FACTORY_ARTIFACT from "../../out/CrowdfundFactory.sol/CrowdfundFactory.json";
import PARTY_FACTORY_ARTIFACT from "../../out/PartyFactory.sol/PartyFactory.json";
import DUMMY_ERC721_ARTIFACT from "../../out/DummyERC721.sol/DummyERC721.json";
import PROPOSAL_EXEUCTION_ENGINE_ARTIFACT from "../../out/ProposalExecutionEngine.sol/ProposalExecutionEngine.json";
import OPENSEA_ARTIFACT from "../../out/IOpenseaExchange.sol/IOpenseaExchange.json";
import ZORA_ARTIFACT from "../../out/IZoraAuctionHouse.sol/IZoraAuctionHouse.json";
import OPENSEA_CONDUIT_CONTROLLER_ARTIFACT from "../../out/IOpenseaConduitController.sol/IOpenseaConduitController.json";
import GLOBALS_ARTIFACT from "../../out/Globals.sol/Globals.json";
import BUY_CF_ARTIFACT from "../../out/BuyCrowdfund.sol/BuyCrowdfund.json";
import COLLECTION_BUY_CF_ARTIFACT from "../../out/CollectionBuyCrowdfund.sol/CollectionBuyCrowdfund.json";
import AUCTION_CF_ARTIFACT from "../../out/AuctionCrowdfund.sol/AuctionCrowdfund.json";
import PARTY_ARTIFACT from "../../out/Party.sol/Party.json";
import TOKEN_DISTRIBUTOR_ARTIFACT from "../../out/TokenDistributor.sol/TokenDistributor.json";
import ERC20_ARTIFACT from "../../out/IERC20.sol/IERC20.json";
import ERC721_ARTIFACT from "../../out/IERC721.sol/IERC721.json";

import {
  DistributionInfo,
  GlobalKeys,
  Proposal,
  ProposalStatus,
  ProposalType,
  TokenType,
} from "../integration/system";
import { OpenseaOrderParams, OpenseaOrderType, OpenseaItemType } from "../integration/seaport";
import {
  ONE_DAY_SECONDS,
  ONE_ETHER,
  NULL_ADDRESS,
  NULL_HASH,
  ZERO,
  NULL_BYTES,
  describeFork,
  describeSnapshot,
  deployContract,
  now,
  runInSnapshot,
  increaseTime,
  createUnlockedWallet,
  mineTx,
  TransactionReceiptWithEvents,
  increaseBalance,
  randomAddress,
  itSnapshot,
} from "../utils";

use(solidity);

interface OpenseaListing {
  parameters: OpenseaOrderParams;
  signature: string;
}

interface GovernanceToken {
  tokenId: BigNumber;
  votingPower: BigNumber;
}

interface MemberInfo {
  wallet: Wallet;
  governanceTokens: GovernanceToken[];
}

interface DeployedAddresses {
  globals: string;
  tokenDistributor: string;
  proposalEngineImpl: string;
  partyFactory: string;
  crowdfundFactory: string;
  zoraMarketWrapper: string;
}

const ALL_INTERFACES = [
  new ethers.utils.Interface(PARTY_ARTIFACT.abi),
  new ethers.utils.Interface(PROPOSAL_EXEUCTION_ENGINE_ARTIFACT.abi),
  new ethers.utils.Interface(BUY_CF_ARTIFACT.abi),
  new ethers.utils.Interface(COLLECTION_BUY_CF_ARTIFACT.abi),
  new ethers.utils.Interface(AUCTION_CF_ARTIFACT.abi),
  new ethers.utils.Interface(CF_FACTORY_ARTIFACT.abi),
  new ethers.utils.Interface(PARTY_FACTORY_ARTIFACT.abi),
  new ethers.utils.Interface(TOKEN_DISTRIBUTOR_ARTIFACT.abi),
  new ethers.utils.Interface(ERC20_ARTIFACT.abi),
  new ethers.utils.Interface(ERC721_ARTIFACT.abi),
  new ethers.utils.Interface(ZORA_ARTIFACT.abi),
  new ethers.utils.Interface(OPENSEA_ARTIFACT.abi),
];

describeFork("Mainnet deployment fork smoke tests", provider => {
  const PARTY_NAME = "ForkParty";
  const PARTY_SYMBOL = "FRK";
  const CF_DURATION = ONE_DAY_SECONDS * 30;
  const NULL_GATEKEEPER_ID = "0x000000000000000000000000";
  const OPENSEA_FEE_RECIPIENT = "0x0000a26b00c1F0DF003000390027140000fAa719";
  const OPENSEA_FEE_BPS = 0.025e4;
  const OPENSEA_DOMAIN_HASH_PREFIX = ethers.utils.hexDataSlice(
    ethers.utils.keccak256(Buffer.from("partyprotocol")),
    0,
    4,
  );
  const SPLIT_BPS = 0.1e4;

  const [worker, deployOwner, buyer, seller, host, splitRecipient, ...users] =
    provider.getWallets();

  const FIXED_GOVERNANCE_OPTS = {
    hosts: [host.address] as string[],
    voteDuration: ONE_DAY_SECONDS * 4,
    executionDelay: ONE_DAY_SECONDS,
    passThresholdBps: 0.51e4,
    feeBps: 0.025e4,
    feeRecipient: deployOwner.address,
  };

  let dummyERC721Contract: Contract;
  let testERC721tokenIds: BigNumber[] = [];
  let deployer: Contract;
  let crowdfundFactory: Contract;
  let proposalEngineImpl: Contract;
  let opensea: Contract;
  let openseaConduitController: Contract;
  let zora: Contract;
  let globals: Contract;
  let distributor: Contract;
  let daoWallet: Contract;
  let zoraMarketWrapperAddress: string;

  before(async () => {
    // Create a test ERC721 contract and some token IDs owned by seller.
    dummyERC721Contract = await deployContract(worker, DUMMY_ERC721_ARTIFACT as any);
    for (let i = 0; i < 10; ++i) {
      const r = await (await dummyERC721Contract.mint(seller.address)).wait();
      testERC721tokenIds.push(r.events.filter((e: any) => e.event === "Transfer")[0].args.tokenId);
    }

    let addresses: DeployedAddresses;
    if (!ENV.DEPLOYED) {
      console.info(`Not using a deployed instance. Deploying contracts on fork...`);
      // Deploy the protocol deployer.
      deployer = await deployContract(worker, DEPLOY_ARTIFACT as any);
      // Deploy the protocol with mainnet config.
      await mineTx(deployer.deployMainnetFork(deployOwner.address));
      addresses = {
        globals: await deployer.globals(),
        proposalEngineImpl: await deployer.proposalEngineImpl(),
        crowdfundFactory: await deployer.crowdfundFactory(),
        partyFactory: await deployer.partyFactory(),
        tokenDistributor: await deployer.tokenDistributor(),
        zoraMarketWrapper: await deployer.zoraMarketWrapper(),
      };
    } else {
      console.info(`Using deployed instance "${ENV.DEPLOYED}"...`);
      // Use deployed addresses.
      const deployed = require(`../../../deploy/deployed-contracts/${ENV.DEPLOYED}.json`);
      addresses = {
        globals: deployed.globals,
        proposalEngineImpl: deployed.proposalEngineImpl,
        crowdfundFactory: deployed.partyCrowdfundFactory,
        partyFactory: deployed.partyFactory,
        tokenDistributor: deployed.tokenDistributor,
        zoraMarketWrapper: deployed.zoraMarketWrapper,
      };
    }

    // Populate deployed contract addresses.
    globals = new Contract(addresses.globals, GLOBALS_ARTIFACT.abi, worker);
    crowdfundFactory = new Contract(addresses.crowdfundFactory, CF_FACTORY_ARTIFACT.abi, worker);
    distributor = new Contract(addresses.tokenDistributor, TOKEN_DISTRIBUTOR_ARTIFACT.abi, worker);
    proposalEngineImpl = new Contract(
      addresses.proposalEngineImpl,
      PROPOSAL_EXEUCTION_ENGINE_ARTIFACT.abi,
      worker,
    );
    opensea = new Contract(await proposalEngineImpl.SEAPORT(), OPENSEA_ARTIFACT.abi, worker);
    zora = new Contract(await proposalEngineImpl.ZORA(), ZORA_ARTIFACT.abi, worker);
    openseaConduitController = new Contract(
      "0x00000000F9490004C11Cef243f5400493c00Ad63",
      OPENSEA_CONDUIT_CONTROLLER_ARTIFACT.abi,
      worker,
    );
    daoWallet = await createUnlockedWallet(
      provider,
      await globals.getAddress(GlobalKeys.DaoMultisig),
      worker,
    );
    FIXED_GOVERNANCE_OPTS.feeRecipient = daoWallet.address;
    zoraMarketWrapperAddress = addresses.zoraMarketWrapper;

    await fundWallets(provider, provider.getWallets(), ONE_ETHER.mul(100));
  });

  describeSnapshot("AuctionCrowdfund", provider, () => {
    const RESERVE_PRICE = ONE_ETHER.div(10);
    const DURATION = ONE_DAY_SECONDS;
    let cf: Contract;
    let buyTokenId: BigNumber;
    let auctionId: BigNumber;
    let nonPreciousTokenId: BigNumber;
    let party: Contract;
    let members: MemberInfo[];
    const contributors = users.slice(0, 3);

    describeSnapshot("zora", provider, () => {
      before(async () => {
        buyTokenId = testERC721tokenIds[0];
        await mineTx(dummyERC721Contract.connect(seller).setApprovalForAll(zora.address, true));
        let r = await mineTx(
          zora
            .connect(seller)
            .createAuction(
              buyTokenId,
              dummyERC721Contract.address,
              DURATION,
              RESERVE_PRICE,
              NULL_ADDRESS,
              0,
              NULL_ADDRESS,
            ),
        );
        auctionId = findEvent(r, "AuctionCreated", zora.address, {
          tokenContract: dummyERC721Contract.address,
          tokenId: buyTokenId,
        }).args.auctionId;

        r = await mineTx(
          crowdfundFactory.createAuctionCrowdfund(
            {
              name: PARTY_NAME,
              symbol: PARTY_SYMBOL,
              customizationPresetId: 0,
              auctionId,
              market: zoraMarketWrapperAddress,
              nftContract: dummyERC721Contract.address,
              nftTokenId: buyTokenId,
              duration: CF_DURATION,
              maximumBid: RESERVE_PRICE.mul(10),
              splitRecipient: splitRecipient.address,
              splitBps: SPLIT_BPS,
              initialContributor: NULL_ADDRESS,
              initialDelegate: NULL_ADDRESS,
              gateKeeper: NULL_ADDRESS,
              gateKeeperId: NULL_GATEKEEPER_ID,
              onlyHostCanBid: true,
              governanceOpts: FIXED_GOVERNANCE_OPTS,
            },
            NULL_BYTES,
          ),
        );
        cf = new Contract(
          findEvent(r, "AuctionCrowdfundCreated", crowdfundFactory.address).args.crowdfund,
          AUCTION_CF_ARTIFACT.abi,
          worker,
        );
      });

      describeSnapshot("winning path", provider, () => {
        itSnapshot("can lose", provider, async () => {
          await contributeEvenly(cf, contributors, RESERVE_PRICE);
          // End auction.
          increaseTime(provider, CF_DURATION);
          // Finalize and lose.
          await cf.callStatic.finalize(FIXED_GOVERNANCE_OPTS);
          let r = await mineTx(cf.finalize(FIXED_GOVERNANCE_OPTS));
          expect(doesEventExist(r, "Lost", cf.address)).to.be.true;
          // Redeem contributions.
          await burnContributors(cf, contributors);
        });

        itSnapshot("can win", provider, async () => {
          await contributeEvenly(cf, contributors, RESERVE_PRICE);
          // Bid on auction.
          let r = await mineTx(cf.connect(host).bid(FIXED_GOVERNANCE_OPTS, 0));
          // End auction.
          increaseTime(provider, DURATION);
          // Finalize and win.
          r = await mineTx(cf.finalize(FIXED_GOVERNANCE_OPTS));
          party = new Contract(
            findEvent(r, "Won", cf.address).args.party,
            PARTY_ARTIFACT.abi,
            worker,
          );
        });
      });
    });
  });

  describeSnapshot("CollectionBuyCrowdfund", provider, () => {
    const LIST_PRICE = ONE_ETHER;
    let cf: Contract;
    let buyTokenId: BigNumber;
    let listing: OpenseaListing;
    let nonPreciousTokenId: BigNumber;
    let party: Contract;
    let members: MemberInfo[];
    const contributors = users.slice(0, 3);

    before(async () => {
      buyTokenId = testERC721tokenIds[0];
      listing = await createOpenseaListing(dummyERC721Contract, buyTokenId, LIST_PRICE);
      let r = await mineTx(
        crowdfundFactory.createCollectionBuyCrowdfund(
          {
            name: PARTY_NAME,
            symbol: PARTY_SYMBOL,
            customizationPresetId: 0,
            nftContract: dummyERC721Contract.address,
            duration: CF_DURATION,
            maximumPrice: LIST_PRICE,
            splitRecipient: splitRecipient.address,
            splitBps: SPLIT_BPS,
            initialContributor: NULL_ADDRESS,
            initialDelegate: NULL_ADDRESS,
            gateKeeper: NULL_ADDRESS,
            gateKeeperId: NULL_GATEKEEPER_ID,
            governanceOpts: FIXED_GOVERNANCE_OPTS,
          },
          NULL_BYTES,
        ),
      );
      cf = new Contract(
        findEvent(r, "CollectionBuyCrowdfundCreated", crowdfundFactory.address).args.crowdfund,
        COLLECTION_BUY_CF_ARTIFACT.abi,
        worker,
      );
    });

    describeSnapshot("winning path", provider, () => {
      it("can win", async () => {
        await contributeEvenly(cf, contributors, LIST_PRICE);

        // buy the NFT
        noise(`\tBuying the NFT...`);
        let r = await mineTx(
          cf
            .connect(host)
            .buy(
              buyTokenId,
              opensea.address,
              LIST_PRICE,
              (
                await opensea.populateTransaction.fulfillOrder(listing, NULL_HASH)
              ).data,
              FIXED_GOVERNANCE_OPTS,
              0,
            ),
        );
        party = new Contract(
          findEvent(r, "Won", cf.address).args.party,
          PARTY_ARTIFACT.abi,
          worker,
        );
      });
    });
  });

  describeSnapshot("BuyCrowdfund", provider, () => {
    const LIST_PRICE = ONE_ETHER;
    let cf: Contract;
    let buyTokenId: BigNumber;
    let nonPreciousTokenId: BigNumber;
    let listing: OpenseaListing;
    let party: Contract;
    let members: MemberInfo[];
    const contributors = users.slice(0, 3);

    before(async () => {
      buyTokenId = testERC721tokenIds[0];
      listing = await createOpenseaListing(dummyERC721Contract, buyTokenId, LIST_PRICE);
      let r = await mineTx(
        crowdfundFactory.createBuyCrowdfund(
          {
            name: PARTY_NAME,
            symbol: PARTY_SYMBOL,
            customizationPresetId: 0,
            nftContract: dummyERC721Contract.address,
            nftTokenId: buyTokenId,
            duration: CF_DURATION,
            maximumPrice: LIST_PRICE,
            splitRecipient: splitRecipient.address,
            splitBps: SPLIT_BPS,
            initialContributor: NULL_ADDRESS,
            initialDelegate: NULL_ADDRESS,
            gateKeeper: NULL_ADDRESS,
            gateKeeperId: NULL_GATEKEEPER_ID,
            governanceOpts: FIXED_GOVERNANCE_OPTS,
          },
          NULL_BYTES,
        ),
      );
      cf = new Contract(
        findEvent(r, "BuyCrowdfundCreated", crowdfundFactory.address).args.crowdfund,
        BUY_CF_ARTIFACT.abi,
        worker,
      );
    });

    describeSnapshot("winning path with governance", provider, () => {
      it("can win", async () => {
        await contributeEvenly(cf, contributors, LIST_PRICE);

        // buy the NFT
        noise(`\tBuying the NFT...`);
        let r = await mineTx(
          cf.buy(
            opensea.address,
            LIST_PRICE,
            (
              await opensea.populateTransaction.fulfillOrder(listing, NULL_HASH)
            ).data,
            FIXED_GOVERNANCE_OPTS,
            0,
          ),
        );
        party = new Contract(
          findEvent(r, "Won", cf.address).args.party,
          PARTY_ARTIFACT.abi,
          worker,
        );
      });

      it("can mint voting powers", async () => {
        // mint voting powers
        members = await burnContributors(cf, [...contributors, splitRecipient]);
      });

      itSnapshot("can sell a governance NFT on OpenSea", provider, async () => {
        const seller = members[0].wallet;
        const token = members[0].governanceTokens[0];
        const listing = await createOpenseaListing(party, token.tokenId, ONE_ETHER.div(10), seller);
        const r = await buyOpenseaListing(listing.parameters);
        expect(
          doesEventExist(r, "Transfer", party.address, {
            owner: members[0].wallet.address,
            to: buyer.address,
          }),
        ).to.be.true;
        const { timestamp } = await provider.getBlock(r.blockNumber);
        expect(await party["getVotingPowerAt(address,uint40)"](seller.address, timestamp)).to.eq(0);
        expect(await party["getVotingPowerAt(address,uint40)"](buyer.address, timestamp)).to.eq(
          token.votingPower,
        );
      });

      it("can mint a token with arbitrary calls", async () => {
        nonPreciousTokenId = await runArbitraryCallToMintTokenTest(party, members, buyTokenId);
      });

      describe("precious-touching proposals", async () => {
        itSnapshot("fractionalize proposal", provider, async () =>
          runFractionalizeTest(party, members, buyTokenId, buyTokenId),
        );
        itSnapshot("opensea proposal", provider, async () =>
          runListOnOpenseaTest(party, members, buyTokenId, buyTokenId),
        );
        itSnapshot("unanimous opensea proposal", provider, async () =>
          runListOnOpenseaTest(party, members, buyTokenId, buyTokenId, true),
        );
        itSnapshot("zora proposal", provider, async () =>
          runListOnZoraTest(party, members, buyTokenId, buyTokenId),
        );
      });

      describe("non-precious touching proposals", async () => {
        itSnapshot("fractionalize proposal", provider, async () =>
          runFractionalizeTest(party, members, buyTokenId, nonPreciousTokenId),
        );
        itSnapshot("opensea proposal", provider, async () =>
          runListOnOpenseaTest(party, members, buyTokenId, nonPreciousTokenId),
        );
        itSnapshot("zora proposal", provider, async () =>
          runListOnZoraTest(party, members, buyTokenId, nonPreciousTokenId),
        );
      });
    });
  });

  async function runArbitraryCallToMintTokenTest(
    party: Contract,
    members: MemberInfo[],
    preciousTokenId: BigNumber,
  ): Promise<BigNumber> {
    noise(`Minting a token with an arbitrary call proposal...`);
    const proposal = buildProposal(
      ProposalType.ArbitraryCalls,
      ethers.utils.defaultAbiCoder.encode(
        ["tuple(address, uint256, bytes, bytes32)[]"],
        [
          [
            [
              dummyERC721Contract.address,
              0,
              (await dummyERC721Contract.populateTransaction.mint(party.address)).data,
              NULL_HASH,
            ],
          ],
        ],
      ),
    );
    const proposalId = await proposeAndAccept(party, proposal, members);
    await increaseTime(provider, FIXED_GOVERNANCE_OPTS.executionDelay);
    // Execute
    const r = await executeProposal(party, members[0], proposalId, proposal, preciousTokenId);
    expect(doesEventExist(r, "ArbitraryCallExecuted", party.address)).to.be.true;
    const { tokenId } = findEvent(r, "Transfer", dummyERC721Contract.address, {
      owner: NULL_ADDRESS,
      to: party.address,
    }).args;
    return tokenId;
  }

  async function runFractionalizeTest(
    party: Contract,
    members: MemberInfo[],
    preciousTokenId: BigNumber,
    tokenId: BigNumber,
  ): Promise<void> {
    noise(`Testing fractional proposal on tokenId ${tokenId.toNumber()}...`);
    const proposal = buildProposal(
      ProposalType.Fractionalize,
      ethers.utils.defaultAbiCoder.encode(
        ["tuple(address, uint256, uint256)"],
        [[dummyERC721Contract.address, tokenId, ONE_ETHER]],
      ),
    );
    const proposalId = await proposeAndAccept(party, proposal, members);
    // Execute
    await increaseTime(provider, FIXED_GOVERNANCE_OPTS.executionDelay);
    const r = await executeProposal(party, members[0], proposalId, proposal, preciousTokenId);

    const fracToken = new Contract(
      findEvent(r, "FractionalV1VaultCreated").args.vault,
      ERC20_ARTIFACT.abi,
      worker,
    );
    // fractional proposal will automatically create a distribution.
    const { info: distInfo } = findEvent(r, "DistributionCreated", distributor.address).args;
    const { totalVotingPower } = await party.getGovernanceValues();
    expect(await fracToken.balanceOf(distributor.address)).to.eq(totalVotingPower);
    await runDistributionTest(party, fracToken, members, distInfo);
  }

  async function runListOnOpenseaTest(
    party: Contract,
    members: MemberInfo[],
    preciousTokenId: BigNumber,
    tokenId: BigNumber,
    passUnanimously: boolean = false,
  ): Promise<void> {
    noise(
      `Testing ${
        passUnanimously ? "(unanimous) " : ""
      }opensea proposal on tokenId ${tokenId.toNumber()}...`,
    );
    const duration = await clampToGlobals(
      ONE_DAY_SECONDS,
      GlobalKeys.OpenSeaMinOrderDuration,
      GlobalKeys.OpenSeaMaxOrderDuration,
    );
    const openseaFee = ONE_ETHER.mul(OPENSEA_FEE_BPS).div(1e4);
    const sellerPrice = ONE_ETHER.sub(openseaFee);
    const proposal = buildProposal(
      ProposalType.ListOnOpenSea,
      ethers.utils.defaultAbiCoder.encode(
        ["tuple(uint256, uint40, address, uint256, uint256[], address[], bytes4)"],
        [
          [
            sellerPrice,
            duration,
            dummyERC721Contract.address,
            tokenId,
            [openseaFee],
            [OPENSEA_FEE_RECIPIENT],
            OPENSEA_DOMAIN_HASH_PREFIX,
          ],
        ],
      ),
    );
    const proposalId = await proposeAndAccept(party, proposal, members, passUnanimously);

    // Execute
    let progressData = NULL_BYTES;
    if (!passUnanimously) {
      await increaseTime(provider, FIXED_GOVERNANCE_OPTS.executionDelay);
      if (preciousTokenId.eq(tokenId)) {
        // List on zora.
        noise("\tListing on zora...");
        const r = await executeProposal(party, members[0], proposalId, proposal, preciousTokenId);
        progressData = findEvent(r, "ProposalExecuted", party.address).args.nextProgressData;
        // Timeout zora auction.
        const timeout = await globals.getUint256(GlobalKeys.OpenSeaZoraAuctionTimeout);
        await increaseTime(provider, timeout.toNumber());
      }
    }
    noise("\tListing on OpenSea...");
    // List on OS.
    let r = await executeProposal(
      party,
      members[0],
      proposalId,
      proposal,
      preciousTokenId,
      progressData,
    );
    const { orderParams } = findEvent(r, "OpenseaOrderListed", party.address).args;
    progressData = findEvent(r, "ProposalExecuted", party.address).args.nextProgressData;

    // Buy on OS.
    await buyOpenseaListing(orderParams);

    // Finalize proposal.
    noise("\tFinalizing proposal...");
    r = await executeProposal(
      party,
      members[0],
      proposalId,
      proposal,
      preciousTokenId,
      progressData,
    );
    const { tokenId: soldTokenId } = findEvent(r, "OpenseaOrderSold", party.address).args;
    expect(soldTokenId).to.eq(tokenId);

    await runDistributionTest(party, null, members);
  }

  async function runListOnZoraTest(
    party: Contract,
    members: MemberInfo[],
    preciousTokenId: BigNumber,
    tokenId: BigNumber,
  ): Promise<void> {
    noise(`Testing zora proposal on tokenId ${tokenId.toNumber()}...`);
    const listPrice = ONE_ETHER;
    const duration = await clampToGlobals(
      ONE_DAY_SECONDS,
      GlobalKeys.ZoraMinAuctionDuration,
      GlobalKeys.ZoraMaxAuctionDuration,
    );
    const timeout = await clampToGlobals(
      ONE_DAY_SECONDS,
      undefined,
      GlobalKeys.ZoraMaxAuctionTimeout,
    );
    const proposal = buildProposal(
      ProposalType.ListOnZora,
      ethers.utils.defaultAbiCoder.encode(
        ["tuple(uint256, uint40, uint40, address, uint256)"],
        [[listPrice, timeout, duration, dummyERC721Contract.address, tokenId]],
      ),
    );
    const proposalId = await proposeAndAccept(party, proposal, members);

    // Execute
    await increaseTime(provider, FIXED_GOVERNANCE_OPTS.executionDelay);
    // List on zora
    noise("\tListing on Zora...");
    let r = await executeProposal(party, members[0], proposalId, proposal, preciousTokenId);
    let progressData = findEvent(r, "ProposalExecuted", party.address).args.nextProgressData;
    const { auctionId } = findEvent(r, "ZoraAuctionCreated", party.address).args;

    // Bid.
    noise("\tBidding on auction...");
    await bidOnZoraListing(auctionId, listPrice);
    // Skip to end.
    await increaseTime(provider, duration.toNumber());
    // Settle.
    noise("Finalizing proposal...");
    r = await executeProposal(
      party,
      members[0],
      proposalId,
      proposal,
      preciousTokenId,
      progressData,
    );
    const { auctionId: soldAuctionId } = findEvent(r, "ZoraAuctionSold", party.address).args;
    expect(soldAuctionId).to.eq(auctionId);

    await runDistributionTest(party, null, members);
  }

  async function runDistributionTest(
    party: Contract,
    erc20: Contract | null,
    members: MemberInfo[],
    distInfo?: DistributionInfo,
  ): Promise<void> {
    noise("Testing distribution...");
    if (!distInfo) {
      // Create a distribution.
      const r = await mineTx(
        party
          .connect(members[0].wallet)
          .distribute(
            erc20 ? TokenType.Erc20 : TokenType.Native,
            erc20 ? erc20.address : NULL_ADDRESS,
            0,
          ),
      );
      distInfo = findEvent(r, "DistributionCreated", distributor.address).args.info;
    }
    // Claim distribution from members.
    noise(`\tClaiming member distributions...`);
    for (const m of members) {
      const r = await mineTx(
        distributor.connect(m.wallet).batchClaim(
          [...new Array(m.governanceTokens.length)].map(() => distInfo),
          m.governanceTokens.map(t => t.tokenId),
        ),
      );
      for (const tok of m.governanceTokens) {
        const claimedAmount = findEvent(r, "DistributionClaimedByPartyToken", distributor.address, {
          party: party.address,
          partyTokenId: tok.tokenId,
        }).args.amountClaimed;
        expect(claimedAmount).to.exist;
        if (erc20) {
          expect(findEvent(r, "Transfer", erc20.address).args.amount).to.eq(claimedAmount);
        }
      }
    }
    // Claim fees from multisig.
    noise(`\tClaiming DAO fee...`);
    const r = await mineTx(
      daoWallet.execCall(
        distributor.address,
        ZERO,
        (
          await distributor.populateTransaction.claimFee(distInfo, daoWallet.address)
        ).data,
      ),
    );
    const claimedAmount = findEvent(r, "DistributionFeeClaimed", distributor.address, {
      feeRecipient: daoWallet.address,
    }).args.amount;
    expect(claimedAmount).to.exist;
    if (erc20) {
      expect(findEvent(r, "Transfer", erc20.address).args.amount).to.eq(claimedAmount);
    }
  }

  async function createOpenseaListing(
    token: Contract,
    tokenId: BigNumber,
    price: BigNumber,
    seller_?: Wallet,
  ): Promise<OpenseaListing> {
    noise(`\tCreating an OpenSea listing for tokenId ${tokenId.toString()}... `);
    seller_ = seller_ || seller;
    const zone = await globals.getAddress(GlobalKeys.OpenSeaZone);
    const conduitKey = await globals.getBytes32(GlobalKeys.OpenSeaConduitKey);
    const [conduit] = await openseaConduitController.getConduit(conduitKey);
    const fee = price.mul(OPENSEA_FEE_BPS).div(1e4);
    const sellerPrice = price.sub(fee);
    const orderParams = {
      offerer: seller_.address,
      zone: zone,
      offer: [
        {
          itemType: OpenseaItemType.ERC721, // ERC721
          token: token.address,
          identifierOrCriteria: tokenId,
          startAmount: BigNumber.from(1),
          endAmount: BigNumber.from(1),
        },
      ],
      consideration: [
        // seller ask
        {
          itemType: OpenseaItemType.NATIVE, // NATIVE
          token: NULL_ADDRESS,
          identifierOrCriteria: ZERO,
          recipient: seller_.address,
          startAmount: sellerPrice,
          endAmount: sellerPrice,
        },
        // OS fee
        {
          itemType: OpenseaItemType.NATIVE, // NATIVE
          token: NULL_ADDRESS,
          identifierOrCriteria: ZERO,
          recipient: OPENSEA_FEE_RECIPIENT,
          startAmount: fee,
          endAmount: fee,
        },
      ],
      orderType:
        zone === NULL_ADDRESS ? OpenseaOrderType.FULL_OPEN : OpenseaOrderType.FULL_RESTRICTED,
      startTime: now(),
      endTime: now() + ONE_DAY_SECONDS * 30,
      zoneHash: NULL_HASH,
      salt: ZERO,
      conduitKey,
    };
    // Approve OS to spend seller tokens.
    await mineTx(token.connect(seller_).setApprovalForAll(conduit, true));
    const order = {
      parameters: {
        ...orderParams,
        totalOriginalConsiderationItems: orderParams.consideration.length,
      },
      signature: NULL_BYTES,
    };
    noise(`\tValidating OpenSea listing... `);
    await mineTx(opensea.connect(seller_).validate([order]));
    return order;
  }

  async function buyOpenseaListing(
    orderParams: OpenseaOrderParams,
  ): Promise<TransactionReceiptWithEvents> {
    noise("\tBuying OpenSea listing...");
    const totalPrice = orderParams.consideration.reduce((a, c) => a.add(c.startAmount), ZERO);
    return await mineTx(
      opensea
        .connect(buyer)
        .fulfillOrder({ parameters: orderParams, signature: NULL_BYTES }, NULL_HASH, {
          value: totalPrice,
        }),
    );
  }

  async function bidOnZoraListing(auctionId: BigNumber, price: BigNumber): Promise<void> {
    await mineTx(zora.connect(buyer).createBid(auctionId, price, { value: price }));
  }

  function decodeEvents(receipt: { logs: any[] }): any[] {
    const decoded: any[] = [];
    for (const log of receipt.logs) {
      if (log.event) {
        decoded.push(log);
        continue;
      }
      for (const iface of ALL_INTERFACES) {
        try {
          const parsed = iface.parseLog(log);
          decoded.push({
            event: parsed.name,
            args: parsed.args,
            logIndex: log.logIndex,
            address: log.address,
          });
          break;
        } catch (err) {}
      }
    }
    return decoded;
  }

  function doesEventExist(
    receipt: { logs: any[] },
    name: string,
    source?: string,
    matchArgs?: { [k: string]: any },
  ): boolean {
    try {
      findEvent(receipt, name, source, matchArgs);
    } catch {
      return false;
    }
    return true;
  }

  function findEvent(
    receipt: { logs: any[] },
    name: string,
    source?: string,
    matchArgs?: { [k: string]: any },
  ): any {
    const e = decodeEvents(receipt).find(e => {
      if (e.event !== name) {
        return false;
      }
      if (source && e.address.toLowerCase() !== source.toLowerCase()) {
        return false;
      }
      if (matchArgs) {
        for (const k in matchArgs) {
          const v = matchArgs[k];
          if (v !== undefined) {
            if (e.args[k] !== v) {
              if (typeof v === "string" && v.startsWith("0x")) {
                if (v.toLowerCase() !== e.args[k].toLowerCase()) {
                  return false;
                }
              } else if (BigNumber.isBigNumber(v)) {
                if (!v.eq(e.args[k])) {
                  return false;
                }
              } else {
                return false;
              }
            }
          }
        }
      }
      return true;
    });
    if (!e) {
      throw new Error(`no event "${name}" in receipt from ${source} with args ${matchArgs}.`);
    }
    return e;
  }

  function buildProposal(proposalType: ProposalType, proposalData: string): Proposal {
    return {
      maxExecutableTime: now() + ONE_DAY_SECONDS * 30,
      cancelDelay: now() + ONE_DAY_SECONDS * 60,
      proposalData: ethers.utils.hexConcat([
        ethers.utils.hexZeroPad(ethers.utils.hexlify(proposalType), 4),
        proposalData,
      ]),
    };
  }

  async function contribute(cf: Contract, contributor: Wallet, contributionValue: BigNumber) {
    // Fund the contributor.
    await increaseBalance(provider, contributor.address, contributionValue);
    // Contribute to the crowdfund.
    await (
      await cf
        .connect(contributor)
        .contribute(contributor.address, NULL_BYTES, { value: contributionValue })
    ).wait();
  }

  async function burnContributors(
    cf: Contract,
    contributorWallets: Wallet[],
  ): Promise<MemberInfo[]> {
    noise(`\tBurning ${contributorWallets.length} crowdfund NFTs...`);
    const partyAddress = await cf.party();
    const r = await mineTx(
      cf.batchBurn(
        contributorWallets.map(m => m.address),
        true,
      ),
    );
    return contributorWallets.map(w => {
      const { votingPower } = findEvent(r, "Burned", cf.address, { contributor: w.address }).args;
      const governanceTokens = [];
      if (votingPower.gt(0)) {
        const { tokenId } = findEvent(r, "Transfer", partyAddress, {
          owner: NULL_ADDRESS,
          to: w.address,
        }).args;
        governanceTokens.push({ tokenId, votingPower });
      }
      return {
        wallet: w,
        governanceTokens: governanceTokens,
      } as MemberInfo;
    });
  }

  async function contributeEvenly(
    cf: Contract,
    contributorWallets: Wallet[],
    totalContribution: BigNumber,
  ) {
    noise(
      `\tContributing ${totalContribution.toString()} across ${
        contributorWallets.length
      } contributors...`,
    );
    const n = contributorWallets.length;
    const contributionValue = totalContribution.add(n - 1).div(n);
    for (const c of contributorWallets) {
      await contribute(cf, c, contributionValue);
    }
  }

  async function proposeAndAccept(
    party: Contract,
    proposal: Proposal,
    members: MemberInfo[],
    passUnanimously: boolean = false,
  ): Promise<BigNumber> {
    // Increase block time so proposal time is not the same as burn time.
    await increaseTime(provider, 1);
    // propose() from the first member and accept() from the rest until it passes.
    let snapIndex = await party.findVotingPowerSnapshotIndex(members[0].wallet.address, now());
    noise(`\tProposing...`);
    let r = await mineTx(party.connect(members[0].wallet).propose(proposal, snapIndex));
    const { timestamp: proposedTime } = await party.provider.getBlock(r.blockNumber);
    const { proposalId } = findEvent(r, "Proposed", party.address).args;
    for (const m of members.slice(1)) {
      noise(`\tVoting from ${m.wallet.address}...`);
      snapIndex = await party.findVotingPowerSnapshotIndex(m.wallet.address, proposedTime);
      r = await mineTx(party.connect(m.wallet).accept(proposalId, snapIndex));
      // If passUnanimously is true, vote from every member.
      if (!passUnanimously && doesEventExist(r, "ProposalPassed", party.address)) {
        break;
      }
    }
    const [status] = await party.getProposalStateInfo(proposalId);
    if (passUnanimously) {
      expect(status).to.eq(ProposalStatus.Ready, "unanimous proposal should be ready");
    } else {
      expect(status).to.eq(ProposalStatus.Passed, "proposal should be passed");
    }
    return proposalId;
  }

  async function executeProposal(
    party: Contract,
    member: MemberInfo,
    proposalId: BigNumber,
    proposal: Proposal,
    preciousTokenId: BigNumber,
    progressData: string = NULL_BYTES,
    extraData: string = NULL_BYTES,
  ): Promise<TransactionReceiptWithEvents> {
    const args = [
      proposalId,
      proposal,
      [dummyERC721Contract.address],
      [preciousTokenId],
      progressData,
      extraData,
    ];
    return await mineTx(party.connect(member.wallet).execute(...args));
  }

  async function clampToGlobals(
    value: number | BigNumber,
    minKey?: GlobalKeys,
    maxKey?: GlobalKeys,
  ): Promise<BigNumber> {
    let clamped = BigNumber.from(value);
    if (minKey) {
      const min = await globals.getUint256(minKey);
      if (min.gt(clamped)) {
        clamped = min;
      }
    }
    if (maxKey) {
      const max = await globals.getUint256(maxKey);
      if (max.lt(clamped)) {
        clamped = max;
      }
    }
    return clamped;
  }

  async function fundWallets(
    provider: MockProvider,
    wallets: Wallet[],
    amount: BigNumber = ONE_ETHER,
  ) {
    return Promise.all(wallets.map(w => increaseBalance(provider, w.address, amount)));
  }

  function noise(...words: any[]) {
    if (ENV.NOISY) {
      console.info(`ℹ`, ...words);
    }
  }
});
