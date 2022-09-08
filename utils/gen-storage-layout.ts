import yargs from 'yargs';
import fs from 'fs/promises';

yargs.command('$0 <artifactSpec>', 'generate storage layout',
    () => yargs.positional('artifactSpec', { type: 'string', describe: 'like \'AuctionCrowdfund.sol/AuctionCrowdfund\'' }),
    async argv => {
        const artifact = JSON.parse(await fs.readFile(`out/${argv.artifactSpec}.json`, 'utf-8'));
        console.log(serializeStorageLayout(artifact.storageLayout));
    },
).argv;

interface StorageLayout {
    storage: StorageItem[];
    types: { [typeName: string]: StorageLayoutTypeInfo };
}

interface StorageLayoutTypeInfo {
    encoding: string;
    label: string;
    numberOfBytes: number;
}

interface StorageItem {
    astId: number,
    contract: string;
    label: string;
    offset: number;
    slot: string;
    type: string;
}

function serializeStorageLayout(layout: StorageLayout): string {
    const fields = [];
    let prevSlot = 0n;
    let nextOffset = 0;
    for (const item of layout.storage) {
        const t = layout.types[item.type];
        const slot = BigInt(item.slot);
        const paddingId = `${prevSlot}_${nextOffset}`;
        fields.push(...serializePaddings(
            paddingId,
            slot - prevSlot - 1n,
            slot != prevSlot ? item.offset : item.offset - nextOffset
        ));
        prevSlot = BigInt(item.slot);
        nextOffset = (item.offset + t.numberOfBytes) % 32;
        fields.push(`${cleanTypeLabel(t.label)} ${item.label}`);
    }
    return fields.map(f => `${f};`).join('\n');
}

function cleanTypeLabel(typeLabel: string): string {
    return typeLabel
        .replace(/\benum\s+/, '')
        .replace(/\bstruct\s+/, '')
        .replace(/\bcontract\s+/, '');
}

function serializePaddings(id: string, slotPadding: bigint, offsetPadding: number): string[] {
    const items = [];
    if (slotPadding > 0n) {
        items.push(`uint256[${slotPadding}] __padding32_${id}`);
    }
    if (offsetPadding > 0) {
        items.push(`bytes${offsetPadding} __padding1_${id}`);
    }
    return items;
}
