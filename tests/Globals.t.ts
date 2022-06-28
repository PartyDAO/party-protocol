import { expect, use } from 'chai';
import { BigNumber, Contract } from 'ethers';
import { MockProvider, solidity } from 'ethereum-waffle';
import GLOBALS_ARTIFACT from '../out/Globals.sol/Globals.json';
import { deployContract } from './utils';

use(solidity);

describe('Globals test', () => {
    const [wallet, multisig] = new MockProvider().getWallets();
    let globalsContract: Contract;

    before(async () => {
        globalsContract = await deployContract(
            wallet,
            GLOBALS_ARTIFACT as any,
            [multisig.address],
        );
    });

    it('returns zero for unset key', async () => {
        const r: BigNumber = await globalsContract.getUint256(randomKey());
        expect(r).to.eq(0);
    });

    it('returns set value for set key', async () => {
        const v = BigNumber.from('10000000000000000000000000');
        const k = randomKey();
        await globalsContract.connect(multisig).setUint256(k, v);
        const r: BigNumber = await globalsContract.getUint256(k);
        expect(r).to.eq(v);
    });

    it('cannot set value if not multisig', async () => {
        const v = BigNumber.from('10000000000000000000000000');
        const k = randomKey();
        const tx = globalsContract.setUint256(k, v);
        return expect(tx).to.be.reverted;
    });
});

function randomKey(): number {
    return Math.floor(Math.random() * 1e4);
}
