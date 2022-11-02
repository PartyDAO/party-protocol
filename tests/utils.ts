import { TransactionResponse, TransactionReceipt } from '@ethersproject/abstract-provider';
import crypto from 'crypto';
import { BigNumber, Contract, ContractFactory, Signer } from 'ethers';
import * as ethers from 'ethers';
import { MockProvider } from 'ethereum-waffle';
import { env as ENV } from 'process';

import UNLOCKED_WALLET_ARTIFACT from '../out/UnlockedWallet.sol/UnlockedWallet.json';

export const NULL_ADDRESS = '0x0000000000000000000000000000000000000000';
export const NULL_HASH = '0x0000000000000000000000000000000000000000000000000000000000000000';
export const ONE_MINUTE_SECONDS = 60;
export const ONE_HOUR_SECONDS = ONE_MINUTE_SECONDS * 60;
export const ONE_DAY_SECONDS = ONE_HOUR_SECONDS * 24;
export const ONE_ETHER = BigNumber.from('10').pow(18);
export const ZERO = BigNumber.from(0);
export const NULL_BYTES = '0x';

export interface TransactionReceiptWithEvents extends TransactionReceipt {
    events: any[];
}

export function randomAddress(): string {
    return '0x' + crypto.randomBytes(20).toString('hex');
}

export function randomUint256(): BigNumber {
    return BigNumber.from(crypto.randomBytes(32));
}

export function now(): number {
    return Math.floor(Date.now() / 1e3);
}

export async function increaseTime(provider: MockProvider, seconds: number): Promise<void> {
    await provider.send('evm_increaseTime', [seconds]);
    await provider.send('evm_mine', []);
}

export async function deployContract(
    signer: Signer,
    artifact: any,
    args: any[] = [],
    overrides?: any,
): Promise<Contract> {
    const cf = new ContractFactory(
        new ethers.utils.Interface(artifact.abi),
        artifact.bytecode.object,
        signer,
    );
    return cf.deploy(...args, ...[overrides ? [overrides] : []]);
}

export function describeFork(name: string, body: (forkProvider: MockProvider) => void) {
    let it = global.it;
    if (!ENV.FORK_URL) {
        console.info('no FORK_URL env var set, skipping forked tests.');
        return;
    }
    global.it = Object.assign(
        (name: string, ...args: any[]) => {
            it(`${name} [⑃]`, ...args);
        },
        global.it,
    );
    const provider = new MockProvider({
        ganacheOptions: {
            fork: { url: ENV.FORK_URL },
            chain: {
                allowUnlimitedContractSize: true,
            },
            miner: {
                blockGasLimit: 100e9,
            },
            wallet: {
                totalAccounts: 256,
                defaultBalance: 100e18,
            }
        },
    });
    describeSnapshot(`${name} [⑃]`, provider, () => body(provider));
}

export function describeSnapshot(name: string, provider: MockProvider, body: () => void) {
    describe(name, () => {
        let snapshot: string;
        beforeEach(async () => {
            snapshot = await provider.send('evm_snapshot', []);
        });
        afterEach(async () => {
            await provider.send('evm_revert', [ snapshot ]);
        });
        body();
    });
}

export async function runInSnapshot(provider: MockProvider, body: () => Promise<void>) {
    let snapshot: string;
    snapshot = await provider.send('evm_snapshot', []);
    await body();
    await provider.send('evm_revert', [ snapshot ]);
}

export async function setBytecode(provider: MockProvider, address: string, bytecode: string) {
    await provider.send('evm_setAccountCode', [address, bytecode]);
}

export async function setBalance(provider: MockProvider, address: string, balance: BigNumber | number) {
    await provider.send('evm_setAccountBalance', [address, ethers.utils.hexlify(balance)]);
}

export async function createUnlockedWallet(provider: MockProvider, address: string): Promise<Contract> {
    await setBytecode(provider, address, UNLOCKED_WALLET_ARTIFACT.deployedBytecode.object);
    return new Contract(address, UNLOCKED_WALLET_ARTIFACT.abi, provider);
}

export async function mineTx
    <
        TArgs extends any[],
        TMethod extends (...args: TArgs) => Promise<TransactionResponse>
    >
    (txReponsePromise: Promise<TransactionResponse>): Promise<TransactionReceiptWithEvents>
{
    return { events: [], ...(await (await txReponsePromise).wait()) };
}

export async function callAndMineTx
    <
        TArgs extends any[],
        TMethod extends (...args: TArgs) => Promise<TransactionResponse>
    >
    (contract: Contract, method: TMethod, ...args: TArgs): Promise<TransactionReceiptWithEvents>
{
    return mineTx(method.call(contract, ...args));
}