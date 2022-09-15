import { expect, use } from 'chai';
import { Contract, BigNumber } from 'ethers';
import { solidity } from 'ethereum-waffle';
import * as ethers from 'ethers';

import DEPLOY_ARTIFACT from '../../out/deploy.sol/DeployFork.json';
import CF_FACTORY_ARTIFACT from '../../out/CrowdfundFactory.sol/CrowdfundFactory.json';
import DUMMY_ERC721_ARTIFACT from '../../out/DummyERC721.sol/DummyERC721.json';

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
    describeSnapshot,
    deployContract,
    now,
    increaseTime,
} from '../utils';

use(solidity);

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
        ...members
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
    let testERC721tokenIds: BigInt[] = [];
    let deployer: Contract;
    let crowdfundFactory: Contract;

    before(async () => {
        // Create a test ERC721 contract and some token IDs.
        dummyERC721Contract = await deployContract(worker, DUMMY_ERC721_ARTIFACT as any);
        for (let i = 0; i < 10; ++i) {
            const r = await (await dummyERC721Contract.mint(worker.address)).wait();
            testERC721tokenIds.push(r.events.filter((e: any) => e.event === 'Transfer')[0].args.tokenId);
        }

        // Deploy the protocol deployer.
        deployer = await deployContract(worker, DEPLOY_ARTIFACT as any);
        // Deploy the protocol with mainnet config.
        await (await deployer.deployMainnetFork(multisig.address)).wait();

        // Populate deployed contract addresses.
        crowdfundFactory = new Contract(
            await deployer.crowdfundFactory(),
            CF_FACTORY_ARTIFACT.abi,
            worker,
        );
    });

    describeSnapshot('BuyCrowdfund', provider, () => {
        const MAX_PRICE = ONE_ETHER.mul(2);
        let cf: Contract;

        before(async () => {
            cf = await (await crowdfundFactory.createBuyCrowdfund(
                {
                    name: PARTY_NAME,
                    symbol: PARTY_SYMBOL,
                    nftContract: dummyERC721Contract.address,
                    nftTokenId: testERC721tokenIds[0],
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
        });

        it('can win', async () => {
            // expect(await deployer.globals()).to.not.eq(NULL_ADDRESS);
        });
    });


});
