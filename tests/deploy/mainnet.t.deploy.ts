import { expect, use } from 'chai';
import { Contract, BigNumber, Wallet } from 'ethers';
import { solidity } from 'ethereum-waffle';
import * as ethers from 'ethers';

import DEPLOY_ARTIFACT from '../../out/deploy.sol/DeployFork.json';
import CF_FACTORY_ARTIFACT from '../../out/CrowdfundFactory.sol/CrowdfundFactory.json';
import DUMMY_ERC721_ARTIFACT from '../../out/DummyERC721.sol/DummyERC721.json';
import PROPOSAL_EXEUCTION_ENGINE_ARTIFACT from '../../out/ProposalExecutionEngine.sol/ProposalExecutionEngine.json';
import OPENSEA_ARTIFACT from '../../out/IOpenseaExchange.sol/IOpenseaExchange.json';
import ZORA_ARTIFACT from '../../out/IZoraAuctionHouse.sol/IZoraAuctionHouse.json';
import OPENSEA_CONDUIT_CONTROLLER_ARTIFACT from '../../out/IOpenseaConduitController.sol/IOpenseaConduitController.json';
import GLOBALS_ARTIFACT from '../../out/Globals.sol/Globals.json';
import BUY_CF_ARTIFACT from '../../out/BuyCrowdfund.sol/BuyCrowdfund.json';
import PARTY_ARTIFACT from '../../out/Party.sol/Party.json';
import TOKEN_DISTRIBUTOR_ARTIFACT from '../../out/TokenDistributor.sol/TokenDistributor.json';
import ERC20_ARTIFACT from '../../out/IERC20.sol/IERC20.json';
import ERC721_ARTIFACT from '../../out/IERC721.sol/IERC721.json';

import {
    GlobalKeys,
    Proposal,
    ProposalStatus,
    ProposalType,
    TokenType,
} from '../integration/system';
import {
    OpenseaOrderParams,
    OpenseaOrderType,
    OpenseaItemType,
} from '../integration/seaport';
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
    randomAddress,
    setBalance,
    mineTx,
    TransactionReceiptWithEvents,
} from '../utils';

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

const ALL_INTERFACES = [
    new ethers.utils.Interface(PARTY_ARTIFACT.abi),
    new ethers.utils.Interface(PROPOSAL_EXEUCTION_ENGINE_ARTIFACT.abi),
    new ethers.utils.Interface(BUY_CF_ARTIFACT.abi),
    new ethers.utils.Interface(CF_FACTORY_ARTIFACT.abi),
    new ethers.utils.Interface(TOKEN_DISTRIBUTOR_ARTIFACT.abi),
    new ethers.utils.Interface(ERC20_ARTIFACT.abi),
    new ethers.utils.Interface(ERC721_ARTIFACT.abi),
]


describeFork('Mainnet deployment fork smoke tests', (provider) => {
    const PARTY_NAME = 'ForkParty';
    const PARTY_SYMBOL = 'FRK';
    const CF_DURATION = ONE_DAY_SECONDS * 30;
    const NULL_GATEKEEPER_ID = '0x000000000000000000000000';
    const OPENSEA_FEE_RECIPIENT = '0x0000a26b00c1F0DF003000390027140000fAa719';
    const OPENSEA_FEE_BPS = 0.025e4;
    const SPLIT_BPS = .10e4;

    const [
        worker,
        multisig,
        buyer,
        seller,
        splitRecipient,
        ...users
    ] = provider.getWallets();

    const FIXED_GOVERNANCE_OPTS = {
        hosts: [] as string[],
        voteDuration: ONE_DAY_SECONDS * 4,
        executionDelay: ONE_DAY_SECONDS,
        passThresholdBps: 0.51e4,
        feeBps: 0.025e4,
        feeRecipient: multisig.address,
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
        await mineTx(deployer.deployMainnetFork(multisig.address));

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
        distributor = new Contract(
            await deployer.tokenDistributor(),
            TOKEN_DISTRIBUTOR_ARTIFACT.abi,
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
        zora = new Contract(
            await proposalEngineImpl.ZORA(),
            ZORA_ARTIFACT.abi,
            worker,
        );
        openseaConduitController = new Contract(
            '0x00000000F9490004C11Cef243f5400493c00Ad63',
            OPENSEA_CONDUIT_CONTROLLER_ARTIFACT.abi,
            worker,
        );
        daoWallet = await createUnlockedWallet(
            provider,
            await globals.getAddress(GlobalKeys.DaoMultisig),
        );
    });

    describeSnapshot('BuyCrowdfund', provider, () => {
        const LIST_PRICE = ONE_ETHER;
        let cf: Contract;
        let buyTokenId: BigNumber;
        let listing: OpenseaListing;
        const contributors = users.slice(0, 3);

        before(async () => {
            buyTokenId = testERC721tokenIds[0];
            listing = await createOpenseaListing(buyTokenId, LIST_PRICE);
            let r = await mineTx(crowdfundFactory.createBuyCrowdfund(
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
            ));
            cf = new Contract(
                findEvent(r, 'BuyCrowdfundCreated', crowdfundFactory.address).args.crowdfund,
                BUY_CF_ARTIFACT.abi,
                worker,
            );
        });

        it('winning path', async () => {
            await contributeEvenly(cf, contributors, LIST_PRICE);
            
            // buy the NFT
            let r = await mineTx(cf.buy(
                opensea.address,
                LIST_PRICE,
                (await opensea.populateTransaction.fulfillOrder(listing, NULL_HASH)).data,
                FIXED_GOVERNANCE_OPTS,
                0,
            ));
            let party = new Contract(
                findEvent(r, 'Won', cf.address).args.party,
                PARTY_ARTIFACT.abi,
                worker,
            );

            // mint voting powers
            const members = await burnContributors(cf, [...contributors, splitRecipient]);

            await runInSnapshot(
                provider,
                async () => runFractionalizeTest(party, members, buyTokenId),
            );
            await runInSnapshot(
                provider,
                async () => runListOnOpenseaTest(party, members, buyTokenId),
            );
            await runInSnapshot(
                provider,
                async () => runListOnZoraTest(party, members, buyTokenId),
            );
        });
    });

    async function runFractionalizeTest(
        party: Contract,
        members: MemberInfo[],
        preciousTokenId: BigNumber,
    ): Promise<void> {
        console.info(`Testing fractional proposal...`);
        const proposal = buildProposal(
            ProposalType.Fractionalize,
            ethers.utils.defaultAbiCoder.encode(
                ['tuple(address, uint256, uint256)'],
                [ [ dummyERC721Contract.address, preciousTokenId, ONE_ETHER ] ],
            ),
        );
        const proposalId = await proposeAndAccept(party, proposal, members);

        // Execute
        await increaseTime(provider, FIXED_GOVERNANCE_OPTS.executionDelay);
        const r = await executeProposal(party, members[0], proposalId, proposal, preciousTokenId);

        const fracToken = new Contract(
            findEvent(r, 'FractionalV1VaultCreated').args.vault,
            ERC20_ARTIFACT.abi,
            worker,
        );
        const { totalVotingPower } = await party.getGovernanceValues();
        expect(await fracToken.balanceOf(party.address)).to.eq(totalVotingPower);
        await runDistributionTest(party, fracToken, members);
    }

    async function runListOnOpenseaTest(
        party: Contract,
        members: MemberInfo[],
        preciousTokenId: BigNumber,
        passUnanimously: boolean = false,
    ): Promise<void> {
        console.info(`Testing opensea proposal...`);
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
                ['tuple(uint256, uint40, address, uint256, uint256[], address[])'],
                [
                    [
                        sellerPrice,
                        duration,
                        dummyERC721Contract.address,
                        preciousTokenId,
                        [openseaFee],
                        [OPENSEA_FEE_RECIPIENT],
                    ],
                ],
            ),
        );
        const proposalId = await proposeAndAccept(party, proposal, members, passUnanimously);

        // Execute
        let progressData = NULL_BYTES;
        if (!passUnanimously) {
            await increaseTime(provider, FIXED_GOVERNANCE_OPTS.executionDelay);
            // List on zora.
            const r = await executeProposal(party, members[0], proposalId, proposal, preciousTokenId);
            progressData = findEvent(r, 'ProposalExecuted', party.address).args.nextProgressData;
            // Timeout zora auction.
            const timeout = await globals.getUint256(GlobalKeys.OpenSeaZoraAuctionTimeout);
            await increaseTime(provider, timeout);
        }
        // List on OS.
        let r = await executeProposal(party, members[0], proposalId, proposal, preciousTokenId, progressData);
        const { orderParams } = findEvent(r, 'OpenseaOrderListed', party.address).args;
        progressData = findEvent(r, 'ProposalExecuted', party.address).args.nextProgressData;
        
        // Buy on OS.
        await _buyOpenseaListing(orderParams);

        // Finalize proposal.
        r = await executeProposal(party, members[0], proposalId, proposal, preciousTokenId, progressData);
        const { tokenId: soldTokenId } = findEvent(r, 'OpenseaOrderSold', party.address).args;
        expect(soldTokenId).to.eq(preciousTokenId);

        await runDistributionTest(party, null, members);
    }

    async function runListOnZoraTest(
        party: Contract,
        members: MemberInfo[],
        preciousTokenId: BigNumber,
    ): Promise<void> {
        console.info(`Testing zora proposal...`);
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
                ['tuple(uint256, uint40, uint40, address, uint256)'],
                [
                    [
                        listPrice,
                        timeout,
                        duration,
                        dummyERC721Contract.address,
                        preciousTokenId,
                    ],
                ],
            ),
        );
        const proposalId = await proposeAndAccept(party, proposal, members);

        // Execute
        await increaseTime(provider, FIXED_GOVERNANCE_OPTS.executionDelay);
        // List on zora
        let r = await executeProposal(party, members[0], proposalId, proposal, preciousTokenId);
        let progressData = findEvent(r, 'ProposalExecuted', party.address).args.nextProgressData;
        const { auctionId } = findEvent(r, 'ZoraAuctionCreated', party.address).args;

        // Bid.
        await _bidOnZoraListing(auctionId, listPrice);
        // Skip to end.
        await increaseTime(provider, duration.toNumber());
        // Settle.
        r = await executeProposal(party, members[0], proposalId, proposal, preciousTokenId, progressData);
        const { auctionId: soldAuctionId } = findEvent(r, 'ZoraAuctionSold', party.address).args;
        expect(soldAuctionId).to.eq(auctionId);

        await runDistributionTest(party, null, members);
    }

    async function runDistributionTest(
        party: Contract,
        erc20: Contract | null,
        members: MemberInfo[],
    ): Promise<void> {
        console.info('Testing distribution...');
        // Create a distribution.
        let r = await (await party.connect(members[0].wallet).distribute(
            erc20 ? TokenType.Erc20 : TokenType.Native,
            erc20 ? erc20.address : NULL_ADDRESS,
            0,
        )).wait();
        const { info: distInfo } =
            findEvent(r, 'DistributionCreated', distributor.address).args;
        // Claim distribution from members.
        for (const m of members) {
            r = await mineTx(
                distributor
                    .connect(m.wallet)
                    .batchClaim(distInfo, m.governanceTokens.map(t => t.tokenId)),
                );
            for (const tok of m.governanceTokens) {
                const claimedAmount =
                    findEvent(
                        r,
                        'DistributionClaimedByPartyToken',
                        distributor.address,
                        { party: party.address, partyTokenId: tok.tokenId },
                    ).args.amountClaimed;
                expect(claimedAmount).to.exist;
                if (erc20) {
                    expect(findEvent(r, 'Transfer', erc20.address).args.amount).to.eq(claimedAmount);
                }
            }
        }
        // Claim fees from multisig.
        r = await mineTx(daoWallet.execCall(
            (await distributor.populateTransaction.claimFee(distInfo, multisig.address)).data,
        ));
        const claimedAmount = findEvent(
            r,
            'DistributionFeeClaimed',
            distributor.address,
            { feeRecipient: multisig.address },
        ).args.claimedAmount;
        expect(claimedAmount).to.exist;
        if (erc20) {
            expect(findEvent(r, 'Transfer', erc20.address).args.amount).to.eq(claimedAmount);
        }
    }

    async function createOpenseaListing(tokenId: BigNumber, price: BigNumber): Promise<OpenseaListing> {
        const zone = await globals.getAddress(GlobalKeys.OpenSeaZone);
        const conduitKey = await globals.getBytes32(GlobalKeys.OpenSeaConduitKey);
        const [conduit,] = await openseaConduitController.getConduit(conduitKey);
        const fee = price.mul(OPENSEA_FEE_BPS).div(1e4);
        const sellerPrice = price.sub(fee);
        const orderParams = {
            offerer: seller.address,
            zone: zone,
            offer: [
                {
                    itemType: OpenseaItemType.ERC721, // ERC721
                    token: dummyERC721Contract.address,
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
                    recipient: seller.address,
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
            orderType: zone === NULL_ADDRESS
                ? OpenseaOrderType.FULL_OPEN
                : OpenseaOrderType.FULL_RESTRICTED,
            startTime: now(),
            endTime: now() + ONE_DAY_SECONDS * 30,
            zoneHash: NULL_HASH,
            salt: ZERO,
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

    async function _buyOpenseaListing(orderParams: OpenseaOrderParams): Promise<void> {
        const totalPrice =
            orderParams.consideration.reduce((a, c) => a.add(c.startAmount), ZERO);
        await (await opensea.connect(buyer).fulfillOrder(
            { parameters: orderParams, signature: NULL_BYTES },
            NULL_HASH,
            { value: totalPrice },
        )).wait();
    }

    async function _bidOnZoraListing(auctionId: BigNumber, price: BigNumber): Promise<void> {
        await (await zora.connect(buyer).createBid(
            auctionId,
            price,
            { value: price },
        )).wait();
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

    function findEvent(receipt: { logs: any[] }, name: string, source?: string, matchArgs?: { [k: string]: any }): any {
        const e = decodeEvents(receipt)
            .find(e => {
                if (e.event !== name) {
                    return false;
                }
                if (source && e.address !== source) {
                    return false;
                }
                if (matchArgs) {
                    for (const k in matchArgs) {
                        const v = matchArgs[k];
                        if (v !== undefined) {
                            if (e.args[k] !== v) {
                                if (typeof(v) === 'string' && v.startsWith('0x')) {
                                    if (v.toLowerCase() !== e.args[k].toLowerCase()) {
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
        setBalance(provider, contributor.address, contributionValue.add(ONE_ETHER));
        // Contribute to the crowdfund.
        await (await cf.connect(contributor).contribute(
            contributor.address,
            NULL_BYTES,
            { value: contributionValue },
        )).wait();
    }

    async function burnContributors(cf: Contract, contributorWallets: Wallet[]): Promise<MemberInfo[]> {
        const partyAddress = await cf.party();
        const r = await mineTx(cf.batchBurn(contributorWallets.map(m => m.address)));
        return contributorWallets.map(w => {
            const { tokenId } = findEvent(r, 'Transfer', partyAddress, { to: w.address });
            const { votingPower } = findEvent(r, 'Burned', cf.address, { contributor: w.address });
            return {
                wallet: w,
                governanceTokens: [{ tokenId, votingPower }],
            } as MemberInfo;
        });
    }

    async function contributeEvenly(cf: Contract, contributorWallets: Wallet[], totalContribution: BigNumber) {
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
        passUnanimously: boolean = false
    ): Promise<BigNumber>
    {
        // propose() from the first member and accept() from the rest until it passes.
        let snapIndex = await party.findVotingPowerSnapshotIndex(members[0].wallet.address, now());
        let r = await mineTx(party.connect(members[0].wallet).propose(proposal, snapIndex));
        const { timestamp: proposedTime } = await party.provider.getBlock(r.blockNumber);
        const { proposalId } = findEvent(r, 'Proposed', party.address).args;
        for (const m of members.slice(1)) {
            snapIndex = await party.findVotingPowerSnapshotIndex(m.wallet.address, proposedTime);
            r = await mineTx(party.connect(m.wallet).accept(proposalId, 0));
            // If passUnanimously is true, vote from every member.
            if (!passUnanimously && findEvent(r, 'ProposalPassed', party.address)) {
                break;
            }
        }
        if (passUnanimously) {
            const [status, ] = await party.getProposalStateInfo(proposalId);
            expect(status).to.eq(ProposalStatus.Ready);
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
        return mineTx(party.connect(member.wallet).execute(
            proposalId,
            proposal,
            [dummyERC721Contract.address],
            [preciousTokenId],
            progressData,
            extraData,
        ));
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
});
