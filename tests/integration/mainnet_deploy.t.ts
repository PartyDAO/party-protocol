import { expect, use } from 'chai';
import { Contract } from 'ethers';
import { solidity } from 'ethereum-waffle';
import * as ethers from 'ethers';

import DEPLOY_ARTIFACT from '../../out/deploy.sol/DeployFork.json';

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
    describeFork,
    deployContract,
    now,
    increaseTime,
} from '../utils';

use(solidity);

describeFork('Mainnet deployment fork tests', (provider) => {
    const [worker, partyHost, minter, multisig, buyer, ...availableVoters] = provider.getWallets();
    let deployer: Contract;

    before(async () => {
    });

    it('can deploy', async () => {
        deployer = await deployContract(worker, DEPLOY_ARTIFACT as any);
        await (await deployer.deployMainnetFork(worker.address)).wait();
        expect(await deployer.globals()).to.not.eq(NULL_ADDRESS);
    });

});
