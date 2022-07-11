import 'colors';
import * as ethers from 'ethers';
import fs from 'fs/promises';
import yargs from 'yargs';
import glob from 'glob-promise';

yargs.command('$0 <hex>', 'decode revert hex',
    yargs => {
        return yargs.positional('hex', { type: 'string' });
    },
    async argv => {
        console.info(`attempting to decode ${argv.hex.bold}...`);
        const artifactPaths = await glob('out/**/*.json');
        const artifactContents = await Promise.all(artifactPaths.map(p => fs.readFile(p, { encoding: 'utf8' })));
        const errorAbis = uniqifyAbi(artifactContents.map(a => JSON.parse(a).abi)
            .filter(v => !!v)
            .map(abi => abi.filter((e: any) => e.type === 'error'))
            .flat(1));
        const iface = new ethers.utils.Interface(errorAbis);
        try {
            const decoded = iface.parseError(argv.hex as any);
            console.info(
                `Successfully decoded as ${decoded.name.green.bold}`,
                JSON.stringify(Object.assign(
                        {},
                        ...Object.entries(decoded.args).map(([k, v]) => {
                            if (!/^\d+$/.test(k)) {
                                return { [k]: serialize(v) };
                            }
                            return {};
                        }),
                    ),
                    null,
                    '  '
                ),
            );
            return;
        } catch (err) {
            if (!err.reason.includes('not found')) {
                throw err;
            }
        }
        console.warn('Could not find matching error ABI!'.red.bold);
    },
).argv;

function uniqifyAbi(abi: any[]): any[] {
    const uniqued = [] as any[];
    for (const e of abi) {
        let isUnique = true;
        for (const o of uniqued) {
            if (isSameAbiEntry(e, o)) {
                isUnique = false;
                break;
            }
        }
        if (isUnique) {
            uniqued.push(e);
        }
    }
    return uniqued;
}

function isSameAbiEntry(a: any, b: any): boolean {
    return a.name === b.name &&
        a.inputs.length === b.inputs.length &&
        a.inputs.every((x: any, i: number) => x.type === b.inputs[i].type);
}

function serialize(v: any): any {
    if (v._isBigNumber) {
        return v.toString();
    }
    if (typeof(v) === 'object') {
        return Object.assign(
            {},
            ...v.entries().map(([ok, ov]: any[]) => ({[ok]: serialize(ov)})),
        );
    }
    return v;
}
