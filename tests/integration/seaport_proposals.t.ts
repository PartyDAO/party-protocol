import { expect, use } from 'chai';
import { Contract } from 'ethers';
import { deployContract, MockProvider, solidity } from 'ethereum-waffle';
import { env as ENV } from 'process';

import {
    Party,
    System,
    createOpenSeaProposal,
    decodeListOnOpenSeaProgressData,
    ProposalState,
    ListOnOpenSeaStep,
} from './system';
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
    const SEAPORT_ADDRESS = '0x00000000006CEE72100D161c57ADA5Bb2be1CA79';
    const ZORA2_ADDRESS = '0xE468cE99444174Bd3bBBEd09209577d25D1ad673';
    const provider = new MockProvider({ ganacheOptions: { fork: ENV.FORK_URL } });
    const [worker, partyHost, minter, admin, multisig, ...availableVoters] = provider.getWallets();
    let sys: System;

    before(async () => {
        sys = await System.createAsync({
            worker,
            daoMultisig: multisig,
            admins: [admin],
            daoSplit: 0.015,
            openSeaAddress: SEAPORT_ADDRESS,
            zoraAuctionHouseV2Address: ZORA2_ADDRESS,
            forcedZoraAuctionTimeout: ONE_DAY_SECONDS,
            forcedZoraAuctionDuration: ONE_DAY_SECONDS / 2,
        });
    });

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
                listPrice: ONE_ETHER.mul(2),
                duration: ONE_DAY_SECONDS,
                token: party.preciousTokens[0].token.address,
                tokenId: party.preciousTokens[0].tokenId,
            },
            now() + ONE_DAY_SECONDS,
        );
        // Propose.
        const proposalId = await voters[0].proposeAsync(proposal);
        expect(await party.getProposalStateAsync(proposalId)).to.eq(ProposalState.Voting);
        // Vote.
        await voters[1].acceptAsync(proposalId);
        expect(await party.getProposalStateAsync(proposalId)).to.eq(ProposalState.Passed);
        // Skip execution delay.
        await increaseTime(provider, party.executionDelay);
        expect(await party.getProposalStateAsync(proposalId)).to.eq(ProposalState.Ready);
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
        expect(await party.getProposalStateAsync(proposalId)).to.eq(ProposalState.Complete);
    });

    it.skip('works when OS sale is successful', async () => {
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
                listPrice: ONE_ETHER.mul(2),
                duration: ONE_DAY_SECONDS,
                token: party.preciousTokens[0].token.address,
                tokenId: party.preciousTokens[0].tokenId,
            },
            now() + ONE_DAY_SECONDS,
        );
        // Propose.
        const proposalId = await voters[0].proposeAsync(proposal);
        expect(await party.getProposalStateAsync(proposalId)).to.eq(ProposalState.Voting);
        // Vote.
        await voters[1].acceptAsync(proposalId);
        expect(await party.getProposalStateAsync(proposalId)).to.eq(ProposalState.Passed);
        // Skip execution delay.
        await increaseTime(provider, party.executionDelay);
        expect(await party.getProposalStateAsync(proposalId)).to.eq(ProposalState.Ready);
        // Execute to list on zora.
        let progressData = await voters[0].executeAsync(proposalId, proposal);
        expect(progressData).to.not.eq(NULL_BYTES);
        let decodedProgressData = decodeListOnOpenSeaProgressData(progressData);
        console.log(decodedProgressData);
        expect(decodedProgressData.step).to.eq(ListOnOpenSeaStep.ListedOnZora);
        // Skip past auction tiemout.
        await increaseTime(provider, decodedProgressData.minExpiry);
        // Execute to retrieve from zora and list on opensea..
        progressData = await voters[0].executeAsync(proposalId, proposal, progressData);
        expect(progressData).to.not.eq(NULL_BYTES);
        decodedProgressData = decodeListOnOpenSeaProgressData(progressData);
        expect(decodedProgressData.step).to.eq(ListOnOpenSeaStep.ListedOnOpenSea);
        expect(decodedProgressData.orderHash).to.not.eq(NULL_HASH);
        // TODO: Buy token...
        progressData = await voters[0].executeAsync(proposalId, proposal, progressData);
        expect(progressData).to.eq(NULL_BYTES);
        expect(await party.getProposalStateAsync(proposalId)).to.eq(ProposalState.Complete);
    });
});
