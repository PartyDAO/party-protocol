import crypto from 'crypto';
import { BigNumber, Contract, ContractFactory, Signer } from 'ethers';
import * as ethers from 'ethers';
import { MockProvider } from 'ethereum-waffle';

export const NULL_ADDRESS = '0x0000000000000000000000000000000000000000';
export const NULL_HASH = '0x0000000000000000000000000000000000000000000000000000000000000000';
export const ONE_MINUTE_SECONDS = 60;
export const ONE_HOUR_SECONDS = ONE_MINUTE_SECONDS * 60;
export const ONE_DAY_SECONDS = ONE_HOUR_SECONDS * 24;
export const ONE_ETHER = BigNumber.from('10').pow(18);
export const ZERO = BigNumber.from(0);
export const NULL_BYTES = '0x';

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
