import { expect, use } from 'chai';
import { Contract } from 'ethers';
import { MockProvider, solidity } from 'ethereum-waffle';
import { Party, System, createArbitraryCallsProposal, ProposalStatus } from './system';
import {
    ONE_DAY_SECONDS,
    ONE_HOUR_SECONDS,
    ONE_ETHER,
    NULL_ADDRESS,
    NULL_HASH,
    ZERO,
    NULL_BYTES,
    deployContract,
    now,
    increaseTime,
    randomAddress,
} from '../utils';

import DUMMY_CALL_TARGET_ARTIFACT from '../../out/DummyCallTarget.sol/DummyCallTarget.json';

use(solidity);

describe('Arbitrary proposals integrations test', () => {
    const provider = new MockProvider();
    const [worker, partyHost, minter, admin, multisig, ...availableVoters] = provider.getWallets();
    let sys: System;
    let callTarget: Contract;

    before(async () => {
        sys = await System.createAsync({
            worker,
            daoMultisig: multisig,
            admins: [admin],
            daoSplit: 0.015,
            forcedZoraAuctionTimeout: ONE_DAY_SECONDS,
            forcedZoraAuctionDuration: ONE_DAY_SECONDS / 2,
        });
        callTarget = await deployContract(
            worker,
            DUMMY_CALL_TARGET_ARTIFACT as any,
        );
    });

    it('works', async () => {
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
            feeRate: 0.04,
            feeRecipient: randomAddress(),
        });
        const voterWallets = availableVoters.slice(0, 2);
        const votingPowers = [ONE_ETHER.mul(33), ONE_ETHER.mul(33)];
        const voters = [];
        for (const [i, w] of voterWallets.entries()) {
            voters.push(await party.createVoterAsync(w, votingPowers[i], NULL_ADDRESS));
        }
        const proposal = createArbitraryCallsProposal(
            [
                {
                    target: callTarget.address,
                    value: ZERO,
                    data: callTarget.interface.encodeFunctionData('foo', [123]),
                    expectedResultHash: NULL_HASH,
                    optional: false,
                },
            ],
            now() +  7 * ONE_DAY_SECONDS,
            now() +  30 * ONE_DAY_SECONDS
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
        // Execute.
        const progressData = await voters[0].executeAsync(proposalId, proposal);
        expect(progressData).to.eq(NULL_BYTES);
        // Prove it executed.
        expect(await callTarget.getX()).to.eq(123);
        expect(await party.getProposalStatusAsync(proposalId)).to.eq(ProposalStatus.Complete);
    });
});
