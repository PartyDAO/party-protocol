import { expect, use } from 'chai';
import { Contract, BigNumber, Wallet } from 'ethers';
import { solidity } from 'ethereum-waffle';
import * as ethers from 'ethers';

import DEPLOY_ARTIFACT from '../../out/deploy.sol/DeployFork.json';
import CF_FACTORY_ARTIFACT from '../../out/CrowdfundFactory.sol/CrowdfundFactory.json';
import DUMMY_ERC721_ARTIFACT from '../../out/DummyERC721.sol/DummyERC721.json';
import PROPOSAL_EXEUCTION_ENGINE_ARTIFACT from '../../out/ProposalExecutionEngine.sol/ProposalExecutionEngine.json';
import OPENSEA_ARTIFACT from '../../out/IOpenseaExchange.sol/IOpenseaExchange.json';
import FRACTIONALV1_FACTORY_ARTIFACT from '../../out/FractionalV1.sol/IFractionalV1VaultFactory.json';
import OPENSEA_CONDUIT_CONTROLLER_ARTIFACT from '../../out/IOpenseaConduitController.sol/IOpenseaConduitController.json';
import GLOBALS_ARTIFACT from '../../out/Globals.sol/Globals.json';
import BUY_CF_ARTIFACT from '../../out/BuyCrowdfund.sol/BuyCrowdfund.json';
import PARTY_ARTIFACT from '../../out/Party.sol/Party.json';
import ERC20_ARTIFACT from '../../out/IERC20.sol/IERC20.json';

import {
    GlobalKeys,
    Party,
    System,
    createOpenSeaProposal,
    decodeListOnOpenSeaProgressData,
    ProposalStatus,
    ListOnOpenSeaStep,
    ProposalType,
} from './system';
import { OpenseaOrderParams } from './seaport';
import {
    ONE_DAY_SECONDS,
    ONE_HOUR_SECONDS,
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
} from '../utils';

use(solidity);

interface OpenseaListing {
    parameters: {
        offerer: string;
        zone: string;
        offer: Array<{
            itemType: number;
            token: string;
            identifierOrCriteria: BigNumber | number;
            startAmount: BigNumber | number;
            endAmount: BigNumber | number;
        }>;
        consideration: Array<{
            itemType: number;
            token: string;
            identifierOrCriteria: BigNumber | number;
            startAmount: BigNumber | number;
            endAmount: BigNumber | number;
            recipient: string;
        }>;
        orderType: number;
        startTime: BigNumber | number;
        endTime: BigNumber | number;
        zoneHash: string;
        salt: BigNumber | number;
        conduitKey: string;
        totalOriginalConsiderationItems: BigNumber | number;
    };
    signature: string;
}

const ALL_INTERFACES = [
    new ethers.utils.Interface(PARTY_ARTIFACT.abi),
    new ethers.utils.Interface(PROPOSAL_EXEUCTION_ENGINE_ARTIFACT.abi),
    new ethers.utils.Interface(BUY_CF_ARTIFACT.abi),
    new ethers.utils.Interface(CF_FACTORY_ARTIFACT.abi),
    new ethers.utils.Interface(FRACTIONALV1_FACTORY_ARTIFACT.abi),
]


describeFork('Mainnet deployment fork tests', (provider) => {
    const PARTY_NAME = 'ForkParty';
    const PARTY_SYMBOL = 'FRK';
    const CF_DURATION = ONE_DAY_SECONDS * 30;
    const SPLIT_BPS = 0.025e4;
    const NULL_GATEKEEPER_ID = '0x000000000000000000000000';

    const [
        worker,
        multisig,
        feeRecipient,
        partyHost,
        minter,
        buyer,
        seller,
        ...users
    ] = provider.getWallets();

    const FIXED_GOVERNANCE_OPTS = {
        hosts: [partyHost.address],
        voteDuration: ONE_DAY_SECONDS * 4,
        executionDelay: ONE_DAY_SECONDS,
        passThresholdBps: 0.51e4,
        feeBps: 0.025e4,
        feeRecipient: feeRecipient.address,
    };

    let dummyERC721Contract: Contract;
    let testERC721tokenIds: BigNumber[] = [];
    let deployer: Contract;
    let crowdfundFactory: Contract;
    let proposalEngineImpl: Contract;
    let opensea: Contract;
    let openseaConduitController: Contract;
    let globals: Contract;

    before(async () => {
        // Create a test ERC721 contract and some token IDs owned by seller.
        dummyERC721Contract = await deployContract(worker, DUMMY_ERC721_ARTIFACT as any);
        for (let i = 0; i < 10; ++i) {
            const r = await (await dummyERC721Contract.mint(seller.address)).wait();
            testERC721tokenIds.push(r.events.filter((e: any) => e.event === 'Transfer')[0].args.tokenId);
        }

        // Deploy the protocol deployer.
        deployer = await deployContract(worker, DEPLOY_ARTIFACT as any);
        // Deploy the protocol with mainnet config.
        await (await deployer.deployMainnetFork(multisig.address)).wait();

        // Populate deployed contract addresses.
        globals = new Contract(
            await deployer.globals(),
            GLOBALS_ARTIFACT.abi,
            worker,
        );
        crowdfundFactory = new Contract(
            await deployer.crowdfundFactory(),
            CF_FACTORY_ARTIFACT.abi,
            worker,
        );
        proposalEngineImpl = new Contract(
            await deployer.proposalEngineImpl(),
            PROPOSAL_EXEUCTION_ENGINE_ARTIFACT.abi,
            worker,
        );
        opensea = new Contract(
            await proposalEngineImpl.SEAPORT(),
            OPENSEA_ARTIFACT.abi,
            worker,
        );
        openseaConduitController = new Contract(
            '0x00000000F9490004C11Cef243f5400493c00Ad63',
            OPENSEA_CONDUIT_CONTROLLER_ARTIFACT.abi,
            worker,
        );
    });

    describeSnapshot('BuyCrowdfund', provider, () => {
        const MAX_PRICE = ONE_ETHER.mul(2);
        const LIST_PRICE = ONE_ETHER;
        let cf: Contract;
        let buyTokenId: BigNumber;
        let listing: OpenseaListing;
        let contributors = users.slice(0, 4);
        let delegate = contributors[0];

        before(async () => {
            buyTokenId = testERC721tokenIds[0];
            listing = await createOpenseaListing(buyTokenId, LIST_PRICE);
            let r = await (await crowdfundFactory.createBuyCrowdfund(
                {
                    name: PARTY_NAME,
                    symbol: PARTY_SYMBOL,
                    nftContract: dummyERC721Contract.address,
                    nftTokenId: buyTokenId,
                    duration: CF_DURATION,
                    maximumPrice: MAX_PRICE,
                    splitRecipient: partyHost.address,
                    splitBps: SPLIT_BPS,
                    initialContributor: NULL_ADDRESS,
                    initialDelegate: NULL_ADDRESS,
                    gateKeeper: NULL_ADDRESS,
                    gateKeeperId: NULL_GATEKEEPER_ID,
                    governanceOpts: FIXED_GOVERNANCE_OPTS,
                },
                NULL_BYTES,
            )).wait();
            cf = new Contract(
                r.events.find((e: any) => e.event === 'BuyCrowdfundCreated').args.crowdfund,
                BUY_CF_ARTIFACT.abi,
                worker,
            );
        });

        it('winning path', async () => {
            // Contribute (more than necessary).
            const individualContribution = MAX_PRICE.div(contributors.length);
            for (const c of contributors) {
                await (await cf.connect(c).contribute(
                    delegate.address,
                    NULL_BYTES,
                    { value: individualContribution },
                )).wait();
            }
            // buy the NFT
            let r = await (await cf.buy(
                opensea.address,
                LIST_PRICE,
                (await opensea.populateTransaction.fulfillOrder(listing, NULL_HASH)).data,
                FIXED_GOVERNANCE_OPTS,
            )).wait();
            let party = new Contract(
                r.events.find((e: any) => e.event === 'Won').args.party,
                PARTY_ARTIFACT.abi,
                worker,
            );
            const { preciousTokens, preciousTokenIds } = findEvent(r, 'PartyInitialized').args;

            expect(preciousTokens).to.deep.eq([dummyERC721Contract.address]);
            expect(preciousTokenIds).to.deep.eq([buyTokenId]);
            expect(await party.name()).to.eq(PARTY_NAME);
            expect(await dummyERC721Contract.ownerOf(buyTokenId)).to.eq(party.address);

            // burn participation NFTs
            const members: Wallet[] = [];
            let totalEthUsed = ZERO;
            for (const c of contributors) {
                r = await (await cf.burn(c.address)).wait();
                const burnedArgs = r.events.find((e: any) => e.event === 'Burned').args;
                totalEthUsed = totalEthUsed.add(burnedArgs.ethUsed);
                if (burnedArgs.ethUsed.gt(0)) {
                    members.push(c);
                }
            }
            expect(totalEthUsed).to.eq(LIST_PRICE);
            const govValues = await party.getGovernanceValues();
            expect(govValues.totalVotingPower).to.eq(LIST_PRICE);

            await runInSnapshot(
                provider,
                async () => runFractionalizeTest(party, members, delegate, buyTokenId),
            );
        });
    });

    async function runFractionalizeTest(
        party: Contract,
        members: Wallet[],
        delegate: Wallet,
        preciousTokenId: BigNumber,
    ): Promise<void> {
        const proposal = {
            maxExecutableTime: now() + ONE_DAY_SECONDS * 30,
            cancelDelay: now() + ONE_DAY_SECONDS * 60,
            proposalData: ethers.utils.hexConcat([
                ethers.utils.hexZeroPad(ethers.utils.hexlify(ProposalType.Fractionalize), 4),
                ethers.utils.defaultAbiCoder.encode(
                    ['address', 'uint256', 'uint256'],
                    [ dummyERC721Contract.address, preciousTokenId, ONE_ETHER],
                ),
            ]),
        };
        let r = await (await party.connect(delegate).propose(proposal, 0)).wait();
        const { proposalId } = findEvent(r, 'Proposed').args;
        expect(findEvent(r, 'ProposalPassed')).to.exist;

        await increaseTime(provider, FIXED_GOVERNANCE_OPTS.executionDelay);
        r = await (await party.connect(delegate).execute(
            proposalId,
            proposal,
            [dummyERC721Contract.address],
            [preciousTokenId],
            NULL_BYTES,
            NULL_BYTES,
        )).wait();
        const fracToken = new Contract(
            findEvent(r, 'Mint').args.vault,
            ERC20_ARTIFACT.abi,
            worker,
        );
        const { totalVotingPower } = await party.getGovernanceValues();
        expect(await fracToken.balanceOf(party.address)).to.eq(totalVotingPower);
        // await runDistributionTest(fracToken, members);
    }

    async function createOpenseaListing(tokenId: BigNumber, price: BigNumber): Promise<OpenseaListing> {
        const zone = await globals.getAddress(GlobalKeys.OpenSeaZone);
        const conduitKey = await globals.getBytes32(GlobalKeys.OpenSeaConduitKey);
        const [conduit,] = await openseaConduitController.getConduit(conduitKey);
        const fee = price.mul(0.025e4).div(1e4);
        const sellerPrice = price.sub(fee);
        const orderParams = {
            offerer: seller.address,
            zone: zone,
            offer: [
                {
                    itemType: 2, // ERC721
                    token: dummyERC721Contract.address,
                    identifierOrCriteria: tokenId,
                    startAmount: 1,
                    endAmount: 1,
                },
            ],
            consideration: [
                // seller ask
                {
                    itemType: 0, // NATIVE
                    token: NULL_ADDRESS,
                    identifierOrCriteria: 0,
                    recipient: seller.address,
                    startAmount: sellerPrice,
                    endAmount: sellerPrice,
                },
                // OS fee
                {
                    itemType: 0, // NATIVE
                    token: NULL_ADDRESS,
                    identifierOrCriteria: 0,
                    recipient: '0x0000a26b00c1F0DF003000390027140000fAa719',
                    startAmount: fee,
                    endAmount: fee,
                },
            ],
            orderType: zone === NULL_ADDRESS
                ? 0  // ETH_TO_ERC721_FULL_OPEN
                : 2, // ETH_TO_ERC1155_FULL_RESTRICTED
            startTime: now(),
            endTime: now() + ONE_DAY_SECONDS * 30,
            zoneHash: NULL_HASH,
            salt: 0,
            conduitKey,
        };
        // Approve OS to spend seller tokens.
        await (await dummyERC721Contract.connect(seller).setApprovalForAll(conduit, true)).wait();
        const order = {
            parameters: {
                ...orderParams,
                totalOriginalConsiderationItems: orderParams.consideration.length,
            },
            signature: NULL_BYTES,
        };
        await (await opensea.connect(seller).validate([order])).wait();
        return order;
    }

    function decodeEvents(receipt: { events: any[] }): any[] {
        const decoded: any[] = [];
        for (const e of receipt.events) {
            if (e.event) {
                decoded.push(e);
                continue;
            }
            for (const iface of ALL_INTERFACES) {
                try {
                    const parsed = iface.parseLog(e);
                    decoded.push({ event: parsed.name, args: parsed.args, logIndex: e.logIndex });
                } catch (err) {}
            }
        }
        return decoded;
    }

    function findEvent(receipt: { events: any[] }, name: string): any {
        const e = decodeEvents(receipt).find(e => e.event === name);
        if (!e) {
            throw new Error(`no event "${name}" in receipt.`);
        }
        return e;
    }
});
