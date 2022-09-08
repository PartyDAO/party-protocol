import { expect, use } from 'chai';
import { Contract } from 'ethers';
import { MockProvider, solidity } from 'ethereum-waffle';
import { env as ENV } from 'process';
import * as ethers from 'ethers';

import { abi as SEAPORT_ABI } from '../../out/IOpenseaExchange.sol/IOpenseaExchange.json';

import {
    Party,
    System,
    createOpenSeaProposal,
    decodeListOnOpenSeaProgressData,
    ProposalStatus,
    ListOnOpenSeaStep,
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
    now,
    increaseTime,
} from '../utils';

use(solidity);

describe('Seaport proposals integrations test', () => {
    let it = global.it;
    if (!ENV.FORK_URL) {
        console.info('no FORK_URL env var set, skipping forked tests.');
        it = it.skip as any;
        (it as any).skip = global.it.skip;
    }
    const SEAPORT_ADDRESS = '0x00000000006c3852cbEf3e08E8dF289169EdE581';
    const SEAPORT_CONDUIT_CONTROLLER_ADDRESS = '0x00000000F9490004C11Cef243f5400493c00Ad63';
    const SEAPORT_CONDUIT_KEY = '0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000';
    const SEAPORT_ZONE_ADDRESS = '0x004C00500000aD104D7DBd00e3ae0A5C00560C00';
    const LIST_PRICE = ethers.utils.parseEther('0.01');
    // OS fee is 2.5% of total considerations (incl OS fee)
    const OS_FEE_RATE_BPS = 0.025e4;
    const OS_FEE = LIST_PRICE.mul(OS_FEE_RATE_BPS).div(1e4 - OS_FEE_RATE_BPS);
    const OS_FEE_RECIPIENT = '0x8De9C5A032463C561423387a9648c5C7BCC5BC90';
    const ZORA2_ADDRESS = '0xE468cE99444174Bd3bBBEd09209577d25D1ad673';
    const provider = new MockProvider({ ganacheOptions: { fork: ENV.FORK_URL } });
    const [worker, partyHost, minter, admin, multisig, buyer, ...availableVoters] = provider.getWallets();
    let seaport: Contract;
    let sys: System;

    before(async () => {
        seaport = new Contract(SEAPORT_ADDRESS, SEAPORT_ABI, buyer);
        sys = await System.createAsync({
            worker,
            daoMultisig: multisig,
            admins: [admin],
            daoSplit: 0.015,
            seaportAddress: SEAPORT_ADDRESS,
            seaportConduitController: SEAPORT_CONDUIT_CONTROLLER_ADDRESS,
            seaportConduitKey: SEAPORT_CONDUIT_KEY,
            seaportZoneAddress: SEAPORT_ZONE_ADDRESS,
            zoraAuctionHouseV2Address: ZORA2_ADDRESS,
            forcedZoraAuctionTimeout: ONE_DAY_SECONDS,
            forcedZoraAuctionDuration: ONE_DAY_SECONDS / 2,
        });
    });

    {
        let snapshot: string;
        beforeEach(async () => {
            snapshot = await provider.send('evm_snapshot', []);
        });
        afterEach(async () => {
            await provider.send('evm_revert', [ snapshot ]);
        });
    }

    it('works with full expiration', async () => {
        const party = await Party.createAsync({
            worker,
            minter,
            executionDelay: 8 * ONE_HOUR_SECONDS,
            voteDuration: ONE_DAY_SECONDS,
            passThreshold: 0.51,
            symbol: 'PRT',
            name: 'PARTY',
            sys: sys,
            hostAddresses: [partyHost.address],
            numPreciousTokens: 2,
            totalVotingPower: ONE_ETHER.mul(100),
        });
        const voterWallets = availableVoters.slice(0, 2);
        const votingPowers = [ONE_ETHER.mul(33), ONE_ETHER.mul(33)];
        const voters = [];
        for (const [i, w] of voterWallets.entries()) {
            voters.push(await party.createVoterAsync(w, votingPowers[i], NULL_ADDRESS));
        }
        const proposal = createOpenSeaProposal(
            {
                listPrice: LIST_PRICE,
                duration: ONE_DAY_SECONDS,
                token: party.preciousTokens[0].token.address,
                tokenId: party.preciousTokens[0].tokenId,
                fees: [OS_FEE],
                feeRecipients: [OS_FEE_RECIPIENT],
            },
            now() + ONE_DAY_SECONDS,
            now() + 30 * ONE_DAY_SECONDS,
        );
        // Propose.
        const proposalId = await voters[0].proposeAsync(proposal);
        expect(await party.getProposalStatusAsync(proposalId)).to.eq(ProposalStatus.Voting);
        // Vote.
        await voters[1].acceptAsync(proposalId);
        expect(await party.getProposalStatusAsync(proposalId)).to.eq(ProposalStatus.Passed);
        // Skip execution delay.
        await increaseTime(provider, party.executionDelay);
        expect(await party.getProposalStatusAsync(proposalId)).to.eq(ProposalStatus.Ready);
        // Execute to list on zora.
        let progressData = await voters[0].executeAsync(proposalId, proposal);
        expect(progressData).to.not.eq(NULL_BYTES);
        let decodedProgressData = decodeListOnOpenSeaProgressData(progressData);
        expect(decodedProgressData.step).to.eq(ListOnOpenSeaStep.ListedOnZora);
        // Skip past auction tiemout.
        await increaseTime(provider, decodedProgressData.minExpiry);
        // Execute to retrieve from zora and list on opensea..
        progressData = await voters[0].executeAsync(proposalId, proposal, progressData);
        expect(progressData).to.not.eq(NULL_BYTES);
        decodedProgressData = decodeListOnOpenSeaProgressData(progressData);
        expect(decodedProgressData.step).to.eq(ListOnOpenSeaStep.ListedOnOpenSea);
        expect(decodedProgressData.orderHash).to.not.eq(NULL_HASH);
        // Skip past OS order expiration.
        await increaseTime(provider, ONE_DAY_SECONDS);
        progressData = await voters[0].executeAsync(proposalId, proposal, progressData);
        expect(progressData).to.eq(NULL_BYTES);
        expect(await party.getProposalStatusAsync(proposalId)).to.eq(ProposalStatus.Complete);
    });

    it('works when OS sale is successful', async () => {
        const party = await Party.createAsync({
            worker,
            minter,
            executionDelay: 8 * ONE_HOUR_SECONDS,
            voteDuration: ONE_DAY_SECONDS,
            passThreshold: 0.51,
            symbol: 'PRT',
            name: 'PARTY',
            sys: sys,
            hostAddresses: [partyHost.address],
            numPreciousTokens: 2,
            totalVotingPower: ONE_ETHER.mul(100),
        });
        const voterWallets = availableVoters.slice(0, 2);
        const votingPowers = [ONE_ETHER.mul(33), ONE_ETHER.mul(33)];
        const voters = [];
        for (const [i, w] of voterWallets.entries()) {
            voters.push(await party.createVoterAsync(w, votingPowers[i], NULL_ADDRESS));
        }
        const proposal = createOpenSeaProposal(
            {
                listPrice: LIST_PRICE,
                duration: ONE_DAY_SECONDS,
                token: party.preciousTokens[0].token.address,
                tokenId: party.preciousTokens[0].tokenId,
                fees: [OS_FEE],
                feeRecipients: [OS_FEE_RECIPIENT],
            },
            now() + ONE_DAY_SECONDS,
            now() + 30 * ONE_DAY_SECONDS,
        );
        // Propose.
        const proposalId = await voters[0].proposeAsync(proposal);
        expect(await party.getProposalStatusAsync(proposalId)).to.eq(ProposalStatus.Voting);
        // Vote.
        await voters[1].acceptAsync(proposalId);
        expect(await party.getProposalStatusAsync(proposalId)).to.eq(ProposalStatus.Passed);
        // Skip execution delay.
        await increaseTime(provider, party.executionDelay);
        expect(await party.getProposalStatusAsync(proposalId)).to.eq(ProposalStatus.Ready);
        // Execute to list on zora.
        let progressData = await voters[0].executeAsync(proposalId, proposal);
        expect(progressData).to.not.eq(NULL_BYTES);
        let decodedProgressData = decodeListOnOpenSeaProgressData(progressData);
        expect(decodedProgressData.step).to.eq(ListOnOpenSeaStep.ListedOnZora);
        // Skip past auction tiemout.
        await increaseTime(provider, decodedProgressData.minExpiry);
        // Execute to retrieve from zora and list on opensea..
        let orderParams: OpenseaOrderParams;
        progressData = await voters[0].executeAsync(
            proposalId,
            proposal,
            progressData,
            NULL_BYTES,
            events => {
                orderParams = events.find(e => e.name == 'OpenseaOrderListed').args[0];
            }
        );
        expect(progressData).to.not.eq(NULL_BYTES);
        decodedProgressData = decodeListOnOpenSeaProgressData(progressData);
        expect(decodedProgressData.step).to.eq(ListOnOpenSeaStep.ListedOnOpenSea);
        expect(decodedProgressData.orderHash).to.not.eq(NULL_HASH);
        expect(decodedProgressData.orderHash).to.eq(
            await seaport.getOrderHash({ ...orderParams, nonce: ZERO })
        );
        await (await seaport.fulfillOrder(
            { parameters: orderParams, signature: NULL_BYTES },
            NULL_HASH,
            { value: LIST_PRICE.add(OS_FEE) },
        )).wait();
        progressData = await voters[0].executeAsync(proposalId, proposal, progressData);
        expect(progressData).to.eq(NULL_BYTES);
        expect(await party.getProposalStatusAsync(proposalId)).to.eq(ProposalStatus.Complete);
    });
});
