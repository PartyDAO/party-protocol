import { Contract, BigNumber, Wallet } from 'ethers';
import * as ethers from 'ethers';
import { deployContract, NULL_ADDRESS, NULL_BYTES, NULL_HASH } from '../utils';

import GLOBALS_ARTIFACT from '../../out/Globals.sol/Globals.json';
import PARTY_FACTORY_ARTIFACT from '../../out/PartyFactory.sol/PartyFactory.json';
import PARTY_ARTIFACT from '../../out/Party.sol/Party.json';
import TOKEN_DIRSTRIBUTOR_ARTIFACT from '../../out/TokenDistributor.sol/TokenDistributor.json';
import PROPOSAL_EXEUCTION_ENGINE_ARTIFACT from '../../out/ProposalExecutionEngine.sol/ProposalExecutionEngine.json';
import PROXY_ARTIFACT from '../../out/Proxy.sol/Proxy.json';
import DUMMY_ERC721_ARTIFACT from '../../out/DummyERC721.sol/DummyERC721.json';
import IERC721_ARTIFACT from '../../out/IERC721.sol/IERC721.json';
import LIST_ON_OPENSEAPORT_PROPOSAL_ARTIFACT from '../../out/ListOnOpenseaProposal.sol/ListOnOpenseaProposal.json';
import IERC20_ARTIFACT from '../../out/IERC20.sol/IERC20.json';

type Event = ethers.utils.LogDescription;

export const artifacts = {
    Globals: GLOBALS_ARTIFACT,
    PartyFactory: PARTY_FACTORY_ARTIFACT,
    Party: PARTY_ARTIFACT,
    TokenDistributor: TOKEN_DIRSTRIBUTOR_ARTIFACT,
    ProposalExecutionEngine: PROPOSAL_EXEUCTION_ENGINE_ARTIFACT,
    Proxy: PROXY_ARTIFACT,
    DummyERC721: DUMMY_ERC721_ARTIFACT,
    IERC721: IERC721_ARTIFACT,
};

const INTERFACES = [
    new ethers.utils.Interface(IERC721_ARTIFACT.abi),
    new ethers.utils.Interface(IERC20_ARTIFACT.abi),
    new ethers.utils.Interface(LIST_ON_OPENSEAPORT_PROPOSAL_ARTIFACT.abi),
    new ethers.utils.Interface(PROPOSAL_EXEUCTION_ENGINE_ARTIFACT.abi),
    new ethers.utils.Interface(PARTY_ARTIFACT.abi),
];

export enum GlobalKeys {
    PartyImpl                   = 1,
    ProposalExecutionEngineImpl = 2,
    PartyFactory                = 3,
    GovernanceNftRendererImpl   = 4,
    CrowdfundNftRendererImpl    = 5,
    OpenSeaZoraAuctionTimeout   = 6,
    OpenSeaZoraAuctionDuration  = 7,
    AuctionCrowdfundImpl        = 8,
    BuyCrowdfundImpl            = 9,
    CollectionBuyCrowdfundImpl  = 10,
    DaoDistributionSplitBps     = 11,
    DaoMultisig                 = 12,
    TokenDistributor            = 13,
    DaoAuthorities              = 14,
    OpenSeaConduitKey           = 15,
    OpenSeaZone                 = 16,
    ProposalMaxCancelDuration   = 17,
    ZoraMinAuctionDuration      = 18
}

export enum ProposalType {
    Invalid                   = 0,
    ListOnOpenSea             = 1,
    ListOnZora                = 2,
    Fractionalize             = 3,
    ArbitraryCalls            = 4,
    UpgradeProposalEngineImpl = 5,
}

export enum ProposalStatus {
    Invalid     = 0,
    Voting      = 1,
    Defeated    = 2,
    Passed      = 3,
    Ready       = 4,
    InProgress  = 5,
    Complete    = 6,
    Cancelled   = 7,
}

export enum ListOnOpenSeaStep {
    None                = 0,
    ListedOnZora        = 1,
    RetrievedFromZora   = 2,
    ListedOnOpenSea     = 3
}

export interface Proposal {
    maxExecutableTime: number;
    cancelDelay: number;
    proposalData: string;
}

export interface ArbitraryCall {
    target: string;
    value: BigNumber;
    data: string;
    optional: boolean;
    expectedResultHash: string;
}

interface OpenSeaProposalInfo {
    listPrice: BigNumber;
    duration: number;
    token: string;
    tokenId: BigNumber,
    fees: BigNumber[];
    feeRecipients: string[];
}

export class System {
    public readonly daoMultisig: Wallet;
    public readonly admin: Wallet;

    static async createAsync(createOpts: {
        worker: Wallet;
        daoMultisig: Wallet;
        admins: Wallet[];
        seaportAddress?: string;
        seaportConduitController?: string;
        seaportZoneAddress?: string;
        seaportConduitKey?: string;
        zoraAuctionHouseV2Address?: string;
        forcedZoraAuctionTimeout?: number;
        forcedZoraAuctionDuration?: number;
        proposalMaxCancelDuration?: number;
        zoraMinAuctionDuration?: number;
        fractionalVaultFactory?: string;
        daoSplit: number;
    }): Promise<System> {
        const worker = createOpts.worker;

        const globals = (await deployContract(
            worker,
            artifacts.Globals as any,
            [worker.address],
        )).connect(worker);
        await (await globals.setAddress(
            GlobalKeys.DaoMultisig,
            createOpts.daoMultisig.address,
        )).wait();
        for (const admin of createOpts.admins) {
            await (await globals.setIncludesAddress(
                GlobalKeys.DaoAuthorities,
                admin.address,
                true
            )).wait();
        }
        await (await globals.setUint256(
            GlobalKeys.DaoDistributionSplitBps,
            Math.floor(createOpts.daoSplit * 1e4),
        )).wait();
        await (await globals.setUint256(
            GlobalKeys.OpenSeaZoraAuctionTimeout,
            createOpts.forcedZoraAuctionTimeout || 0,
        )).wait();
        await (await globals.setUint256(
            GlobalKeys.OpenSeaZoraAuctionDuration,
            createOpts.forcedZoraAuctionDuration || 0,
        )).wait();
        await (await globals.setUint256(
            GlobalKeys.OpenSeaZoraAuctionDuration,
            createOpts.forcedZoraAuctionDuration || 0,
        )).wait();
        await (await globals.setBytes32(
            GlobalKeys.OpenSeaConduitKey,
            createOpts.seaportConduitKey || NULL_HASH,
        )).wait();
        await (await globals.setAddress(
            GlobalKeys.OpenSeaZone,
            createOpts.seaportZoneAddress || NULL_ADDRESS,
        )).wait();
        await (await globals.setUint256(
            GlobalKeys.ProposalMaxCancelDuration,
            createOpts.proposalMaxCancelDuration || 0,
        )).wait();
        await (await globals.setUint256(
            GlobalKeys.ZoraMinAuctionDuration,
            createOpts.zoraMinAuctionDuration || 0,
        )).wait();
        let seaportAddress = createOpts.seaportAddress || NULL_ADDRESS;
        // TODO: could be nice
        // if (!seaportAddress || seaportAddress == NULL_ADDRESS) {
        //     seaportAddress = (await deployContract(
        //         worker,
        //         DUMMY_OPENSEA_ARTIFACT as any,
        //         [],
        //     )).address;
        // }

        const proposalExecutionEngine = await deployContract(
            worker,
            artifacts.ProposalExecutionEngine as any,
            [
                globals.address,
                seaportAddress,
                createOpts.seaportConduitController || NULL_ADDRESS,
                createOpts.zoraAuctionHouseV2Address || NULL_ADDRESS,
                createOpts.fractionalVaultFactory || NULL_ADDRESS,
            ],
        );

        await (await globals.setAddress(
            GlobalKeys.ProposalExecutionEngineImpl,
            proposalExecutionEngine.address,
        )).wait();

        const tokenDistributor = await deployContract(
            worker,
            artifacts.TokenDistributor as any,
            [globals.address],
        );
        await (await globals.setAddress(
            GlobalKeys.TokenDistributor,
            tokenDistributor.address,
        )).wait();

        const party = await deployContract(
            worker,
            artifacts.Party as any,
            [globals.address],
        );
        await (await globals.setAddress(
            GlobalKeys.PartyImpl,
            party.address,
        )).wait();

        const partyFactory = await deployContract(
            worker,
            artifacts.PartyFactory as any,
            [globals.address],
        );
        await (await globals.setAddress(
            GlobalKeys.PartyFactory,
            partyFactory.address,
        )).wait();

        await (await globals.transferMultiSig(createOpts.daoMultisig.address)).wait();

        return new System({
            globals: globals.connect(createOpts.daoMultisig),
            partyFactory,
            tokenDistributor,
            proposalExecutionEngine,
        });
    }

    public readonly globals: Contract;
    public readonly partyFactory: Contract;
    public readonly tokenDistributor: Contract;
    public readonly proposalExecutionEngine: Contract;

    private constructor(initOpts: {
        globals: Contract;
        partyFactory: Contract;
        tokenDistributor: Contract;
        proposalExecutionEngine: Contract;
    }) {
        this.globals = initOpts.globals;
        this.partyFactory = initOpts.partyFactory;
        this.tokenDistributor = initOpts.tokenDistributor;
        this.proposalExecutionEngine = initOpts.proposalExecutionEngine;
    }

}

export class Party {
    public static async createAsync(opts: {
        worker: Wallet,
        minter: Wallet;
        sys: System,
        name: string;
        symbol: string;
        numPreciousTokens: number,
        hostAddresses: string[],
        voteDuration: number;
        executionDelay: number;
        passThreshold: number;
        totalVotingPower: BigNumber;
        feeRate?: number;
        feeRecipient?: string;
    }): Promise<Party> {
        const preciousTokens = await createDummyERC721TokensAsync(
            opts.worker,
            2,
            opts.worker.address,
        );
        const partyFactory = opts.sys.partyFactory.connect(opts.worker);
        const tx = await (await partyFactory.createParty(
            opts.worker.address,
            {
                name: opts.name,
                symbol: opts.symbol,
                governance: {
                    hosts: opts.hostAddresses,
                    voteDuration: opts.voteDuration,
                    executionDelay: opts.executionDelay,
                    passThresholdBps: Math.floor(opts.passThreshold * 1e4),
                    totalVotingPower: opts.totalVotingPower,
                    feeBps: Math.floor((opts.feeRate || 0) * 1e4),
                    feeRecipient: opts.feeRecipient || NULL_ADDRESS,
                },
            },
            preciousTokens.map(({ token }) => token.address),
            preciousTokens.map(({ tokenId}) => tokenId),
        )).wait();
        const partyAddress = tx.events.find((e: any) => e.event === 'PartyCreated').args[0];
        for (const { token, tokenId } of preciousTokens) {
            await (await token.transferFrom(opts.worker.address, partyAddress, tokenId)).wait();
        }
        const party = new Contract(partyAddress, PARTY_ARTIFACT.abi, opts.worker);
        return new Party({
            contract: party,
            minter: opts.minter,
            sys: opts.sys,
            preciousTokens,
            hostAddresses: opts.hostAddresses,
            voteDuration: opts.voteDuration,
            executionDelay: opts.executionDelay,
            passThreshold: opts.passThreshold,
            totalVotingPower: opts.totalVotingPower,
        });
    }

    public readonly contract: Contract;
    public readonly minter: Wallet;
    public readonly sys: System;
    public readonly preciousTokens: Array<{token: Contract; tokenId: BigNumber;}>;
    public readonly hostAddresses: string[];
    public readonly voteDuration: number;
    public readonly executionDelay: number;
    public readonly passThreshold: number;
    public readonly totalVotingPower: BigNumber;

    private constructor(opts: {
        contract: Contract;
        minter: Wallet;
        sys: System;
        preciousTokens: Array<{token: Contract; tokenId: BigNumber;}>;
        hostAddresses: string[];
        voteDuration: number;
        executionDelay: number;
        passThreshold: number;
        totalVotingPower: BigNumber;
    }) {
        this.contract = opts.contract;
        this.minter = opts.minter;
        this.sys = opts.sys;
        this.preciousTokens = opts.preciousTokens.slice();
        this.hostAddresses = opts.hostAddresses;
        this.voteDuration = opts.voteDuration;
        this.executionDelay = opts.executionDelay;
        this.passThreshold = opts.passThreshold;
        this.totalVotingPower = opts.totalVotingPower;
    }

    public get address(): string {
        return this.contract.address;
    }

    public async createVoterAsync(
        wallet: Wallet,
        votingPower: BigNumber,
        delegateAddress: string,
    ): Promise<Voter> {
        const tx = await (await this.contract.mint(
            wallet.address,
            votingPower,
            delegateAddress,
        )).wait();
        const transferEvents = parseLogs(tx.logs).filter(e => e.name == 'Transfer');
        const tokenId = transferEvents.filter(e => e.args[0] === NULL_ADDRESS)[0].args[2];
        return new Voter(
            wallet,
            this,
            tokenId,
            votingPower,
        );
    }

    public async getProposalStatusAsync(proposalId: BigNumber): Promise<ProposalStatus> {
        const [status] = await this.contract.connect(this.minter).getProposalStateInfo(proposalId);
        return status as ProposalStatus;
    }

    public async findLatestVotingPowerSnapshotIndexAsync(memberAddress: string): Promise<BigInt> {
        return await this.contract.findVotingPowerSnapshotIndex(
            memberAddress,
            Math.floor(Date.now() / 1000),
        );
    }
}

export class Voter {
    public constructor(
        public readonly wallet: Wallet,
        public readonly party: Party,
        public readonly tokenId: BigNumber,
        public readonly votingPower: BigNumber,
    ) {}

    public get address(): string {
        return this.wallet.address;
    }

    public async proposeAsync(proposal: Proposal): Promise<BigNumber> {
        const snapIndex = await this.party.findLatestVotingPowerSnapshotIndexAsync(this.address);
        const tx = await (await this.party.contract.connect(this.wallet).propose(
            proposal,
            snapIndex,
        )).wait();
        return tx.events.find((e: any) => e.event === 'Proposed').args[0];
    }

    public async acceptAsync(proposalId: BigNumber): Promise<boolean> {
        const snapIndex = await this.party.findLatestVotingPowerSnapshotIndexAsync(this.address);
        const tx = await (await this.party.contract.connect(this.wallet).accept(
            proposalId,
            snapIndex,
        )).wait();
        return !!tx.events.find((e: any) => e.event === 'ProposalPassed');
    }

    public async executeAsync(
        proposalId: BigNumber,
        proposal: Proposal,
        progressData: string = NULL_BYTES,
        extraData: string = NULL_BYTES,
        eventsHandler?: (events: Event[]) => void,
    ): Promise<string> {
        const tx = await (await this.party.contract.connect(this.wallet).execute(
            proposalId,
            proposal,
            this.party.preciousTokens.map(p => p.token.address),
            this.party.preciousTokens.map(p => p.tokenId),
            progressData,
            extraData,
        )).wait();
        const events = parseLogs(tx.logs);
        if (eventsHandler) {
            eventsHandler(events);
        }
        const progressEvent = events.find(e => e.name === 'ProposalExecuted');
        let nextProgressData = NULL_BYTES;
        if (progressEvent) {
            nextProgressData = progressEvent.args.nextProgressData;
        }
        return nextProgressData;
    }
}

function parseLogs(logs: any[]): Event[] {
    const events = [];
    for (const log of logs) {
        for (const iface of INTERFACES) {
            try {
                events.push(iface.parseLog(log));
            } catch {}
        }
    }
    return events;
}

export async function createDummyERC721TokensAsync(
    worker: Wallet,
    count: number,
    owner: string,
): Promise<Array<{token: Contract; tokenId: BigNumber}>> {
    const r: Array<{token: Contract; tokenId: BigNumber}> = [];
    for (let i = 0; i < count; ++i) {
        const t = (await deployContract(
            worker,
            DUMMY_ERC721_ARTIFACT as any,
        )).connect(worker);
        const tx = await (await t.mint(owner)).wait();
        const tid = tx.events.find((e: any) => e.event === 'Transfer').args[2];
        r.push({ token: t, tokenId: tid });
    }
    return r;
}

export function createArbitraryCallsProposal(calls: ArbitraryCall[], maxExecutableTime: number, cancelDelay: number): Proposal {
    return {
        maxExecutableTime,
        cancelDelay,
        proposalData: ethers.utils.hexConcat([
            ethers.utils.hexZeroPad(ethers.utils.hexlify(ProposalType.ArbitraryCalls), 4),
            ethers.utils.defaultAbiCoder.encode(
                ['tuple(address target,uint256 value,bytes data,bool optional,bytes32 expectedResultHash)[]'],
                [calls],
            ),
        ]),
    };
}

export function createOpenSeaProposal(info: OpenSeaProposalInfo, maxExecutableTime: number, cancelDelay: number): Proposal {
    return {
        maxExecutableTime,
        cancelDelay,
        proposalData: ethers.utils.hexConcat([
            ethers.utils.hexZeroPad(ethers.utils.hexlify(ProposalType.ListOnOpenSea), 4),
            ethers.utils.defaultAbiCoder.encode(
                ['tuple(uint256 listPrice,uint40 duration,address token,uint256 tokenId,uint256[] fees,address[] feeRecipients)'],
                [info],
            ),
        ]),
    };
}

export function decodeListOnOpenSeaProgressData(data: string): { step: ListOnOpenSeaStep; } & any {
    const step = ethers.utils.defaultAbiCoder.decode(['uint8'], data)[0] as ListOnOpenSeaStep;
    if (step == ListOnOpenSeaStep.ListedOnZora) {
        const decoded = ethers.utils.defaultAbiCoder.decode(['uint8','tuple(uint256,uint40)'], data);
        return {
            step,
            auctionId: decoded[1][0],
            minExpiry: decoded[1][1],
        };
    } else if (step == ListOnOpenSeaStep.ListedOnOpenSea) {
        const decoded = ethers.utils.defaultAbiCoder.decode(['uint8','tuple(bytes32,uint40)'], data);
        return {
            step,
            orderHash: decoded[1][0],
            expiry: decoded[1][1],
        };
    }
    throw new Error(`Invalid ListOnOpenSea step: ${step}`);
}
