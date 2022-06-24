import { Contract, BigNumber, Wallet } from 'ethers';
import * as ethers from 'ethers';
import { deployContract } from 'ethereum-waffle';

import { NULL_ADDRESS, NULL_BYTES, randomUint256 } from '../utils';

import GLOBALS_ARTIFACT from '../../out/Globals.sol/Globals.json';
import PARTY_FACTORY_ARTIFACT from '../../out/PartyFactory.sol/PartyFactory.json';
import PARTY_ARTIFACT from '../../out/Party.sol/Party.json';
import TOKEN_DIRSTRIBUTOR_ARTIFACT from '../../out/TokenDistributor.sol/TokenDistributor.json';
import PROPOSAL_EXEUCTION_ENGINE_ARTIFACT from '../../out/ProposalExecutionEngine.sol/ProposalExecutionEngine.json';
import PROXY_ARTIFACT from '../../out/Proxy.sol/Proxy.json';
import DUMMY_ERC721_ARTIFACT from '../../out/DummyERC721.sol/DummyERC721.json';
import IERC721_ARTIFACT from '../../out/IERC721.sol/IERC721.json';

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

export const erc721Interface = new ethers.utils.Interface(IERC721_ARTIFACT.abi);
export const proposalExecutionEngineInterface = new ethers.utils.Interface(PROPOSAL_EXEUCTION_ENGINE_ARTIFACT.abi);

export enum GlobalKeys {
    PartyImpl                   = 1,
    ProposalExecutionEngineImpl = 2,
    PartyFactory                = 3,
    GovernanceNftRendererImpl   = 4,
    CrowdfundNftRendererImpl    = 5,
    OpenSeaZoraAuctionTimeout   = 6,
    OpenSeaZoraAuctionDuration  = 7,
    PartyBidImpl                = 8,
    PartyBuyImpl                = 9,
    PartyCollectionBuyImpl      = 10,
    DaoDistributionSplitBps     = 11,
    DaoMultisig                 = 12,
    TokenDistributor            = 13,
    DaoAuthorities              = 14,
}

export enum ProposalType {
    Invalid                   = 0,
    ListOnOpenSea             = 1,
    ListOnZora                = 2,
    Fractionalize             = 3,
    ArbitraryCalls            = 4,
    UpgradeProposalEngineImpl = 5,
}

export enum ProposalState {
    Invalid     = 0,
    Voting      = 1,
    Defeated    = 2,
    Passed      = 3,
    Ready       = 4,
    InProgress  = 5,
    Complete    = 6,
}

export enum ListOnOpenSeaStep {
    None                = 0,
    ListedOnZora        = 1,
    RetrievedFromZora   = 2,
    ListedOnOpenSea     = 3
}

export interface Proposal {
    maxExecutableTime: number;
    nonce: BigNumber;
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
}

export class System {
    public readonly daoMultisig: Wallet;
    public readonly admin: Wallet;

    static async createAsync(createOpts: {
        worker: Wallet;
        daoMultisig: Wallet;
        admins: Wallet[];
        openSeaAddress?: string;
        zoraAuctionHouseV2Address?: string;
        forcedZoraAuctionTimeout: number;
        forcedZoraAuctionDuration: number;
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
            createOpts.forcedZoraAuctionTimeout,
        )).wait();
        await (await globals.setUint256(
            GlobalKeys.OpenSeaZoraAuctionDuration,
            createOpts.forcedZoraAuctionDuration,
        )).wait();
        let openSeaAddress = createOpts.openSeaAddress || NULL_ADDRESS;
        // TODO: could be nice
        // if (!openSeaAddress || openSeaAddress == NULL_ADDRESS) {
        //     openSeaAddress = (await deployContract(
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
                openSeaAddress,
                createOpts.zoraAuctionHouseV2Address || NULL_ADDRESS,
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
        const tx = await (await this.sys.partyFactory.mint(
            this.address,
            wallet.address,
            votingPower,
            delegateAddress,
        )).wait();
        const transferEvents = getTransferEventsFromReceipt(tx);
        const tokenId = transferEvents.filter(e => e.from === NULL_ADDRESS)[0].id;
        return new Voter(
            wallet,
            this,
            tokenId,
            votingPower,
        );
    }

    public async getProposalStateAsync(proposalId: BigNumber): Promise<ProposalState> {
        const [state] = await this.contract.connect(this.minter).getProposalStates(proposalId);
        return state as ProposalState;
    }
}

export class Voter {
    public constructor(
        public readonly wallet: Wallet,
        public readonly party: Party,
        public readonly tokenId: BigNumber,
        public readonly votingPower: BigNumber,
    ) {}

    public async proposeAsync(proposal: Proposal): Promise<BigNumber> {
        const tx = await (await this.party.contract.connect(this.wallet).propose(
            proposal,
        )).wait();
        return tx.events.find((e: any) => e.event === 'Proposed').args[0];
    }

    public async acceptAsync(proposalId: BigNumber): Promise<boolean> {
        const tx = await (await this.party.contract.connect(this.wallet).accept(
            proposalId,
        )).wait();
        return !!tx.events.find((e: any) => e.event === 'ProposalPassed');
    }

    public async executeAsync(
        proposalId: BigNumber,
        proposal: Proposal,
        progressData: string = NULL_BYTES,
    ): Promise<string> {
        const tx = await (await this.party.contract.connect(this.wallet).execute(
            proposalId,
            proposal,
            this.party.preciousTokens.map(p => p.token.address),
            this.party.preciousTokens.map(p => p.tokenId),
            progressData,
        )).wait();
        if (tx.events.find((e: any) => e.event === 'ProposalCompleted' && proposalId.eq(e.args[0]))) {
            return NULL_BYTES;
        }
        return getProposalExecutionProgressEventsFromReceipt(tx)
            .filter(e => proposalId.eq(e.proposalId))[0].progressData;
    }
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

export function getTransferEventsFromReceipt(
    receipt: { logs: Array<{ data: string; topics: string[]; }> }
): Array<{
    from: string;
    to: string;
    id: BigNumber;
}> {
    const events = [];
    for (const log of receipt.logs) {
        try {
            const r = erc721Interface.parseLog(log);
            if (r.name === 'Transfer') {
                events.push({ from: r.args[0], to: r.args[1], id: r.args[2] });
            }
        } catch {}
    }
    return events;
}

export function getProposalExecutionProgressEventsFromReceipt(
    receipt: { logs: Array<{ data: string; topics: string[]; }> }
): Array<{
    proposalId: BigNumber;
    progressData: string;
}> {
    const events = [];
    for (const log of receipt.logs) {
        try {
            const r = proposalExecutionEngineInterface.parseLog(log);
            if (r.name === 'ProposalExecutionProgress') {
                events.push({ proposalId: r.args[0], progressData: r.args[1] });
            }
        } catch {}
    }
    return events;
}

export function createArbitraryCallsProposal(calls: ArbitraryCall[], maxExecutableTime: number): Proposal {
    return {
        maxExecutableTime,
        nonce: randomUint256(),
        proposalData: ethers.utils.hexConcat([
            ethers.utils.hexZeroPad(ethers.utils.hexlify(ProposalType.ArbitraryCalls), 4),
            ethers.utils.defaultAbiCoder.encode(
                ['tuple(address target,uint256 value,bytes data,bool optional,bytes32 expectedResultHash)[]'],
                [calls],
            ),
        ]),
    };
}

export function createOpenSeaProposal(info: OpenSeaProposalInfo, maxExecutableTime: number): Proposal {
    return {
        maxExecutableTime,
        nonce: randomUint256(),
        proposalData: ethers.utils.hexConcat([
            ethers.utils.hexZeroPad(ethers.utils.hexlify(ProposalType.ListOnOpenSea), 4),
            ethers.utils.defaultAbiCoder.encode(
                ['tuple(uint256 listPrice,uint40 duration,address token,uint256 tokenId)'],
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
