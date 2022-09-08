import { BigNumber } from 'ethers';

export enum OpenseaItemType {
    NATIVE                    = 0,
    ERC20                     = 1,
    ERC721                    = 2,
    ERC1155                   = 3,
    ERC721_WITH_CRITERIA      = 4,
    ERC1155_WITH_CRITERIA     = 5,
}

export enum OpenseaBasicOrderType {
    ETH_TO_ERC721_FULL_OPEN             = 0,
    ETH_TO_ERC721_PARTIAL_OPEN          = 1,
    ETH_TO_ERC721_FULL_RESTRICTED       = 2,
    ETH_TO_ERC721_PARTIAL_RESTRICTED    = 3,
    ETH_TO_ERC1155_FULL_OPEN            = 4,
    ETH_TO_ERC1155_PARTIAL_OPEN         = 5,
    ETH_TO_ERC1155_FULL_RESTRICTED      = 6,
    ETH_TO_ERC1155_PARTIAL_RESTRICTED   = 7,
    ERC20_TO_ERC721_FULL_OPEN           = 8,
    ERC20_TO_ERC721_PARTIAL_OPEN        = 9,
    ERC20_TO_ERC721_FULL_RESTRICTED     = 10,
    ERC20_TO_ERC721_PARTIAL_RESTRICTED  = 11,
    ERC20_TO_ERC1155_FULL_OPEN          = 12,
    ERC20_TO_ERC1155_PARTIAL_OPEN       = 13,
    ERC20_TO_ERC1155_FULL_RESTRICTED    = 14,
    ERC20_TO_ERC1155_PARTIAL_RESTRICTED = 16,
    ERC721_TO_ERC20_FULL_OPEN           = 17,
    ERC721_TO_ERC20_PARTIAL_OPEN        = 18,
    ERC721_TO_ERC20_FULL_RESTRICTED     = 19,
    ERC721_TO_ERC20_PARTIAL_RESTRICTED  = 20,
    ERC1155_TO_ERC20_FULL_OPEN          = 21,
    ERC1155_TO_ERC20_PARTIAL_OPEN       = 22,
    ERC1155_TO_ERC20_FULL_RESTRICTED    = 23,
    ERC1155_TO_ERC20_PARTIAL_RESTRICTED = 24,
}

export enum OpenseaOrderType {
    FULL_OPEN          = 0,
    PARTIAL_OPEN       = 1,
    FULL_RESTRICTED    = 2,
    PARTIAL_RESTRICTED = 3,
}

export interface OpenseaConsiderationItem {
    itemType: OpenseaItemType;
    token: string;
    identifierOrCriteria: BigNumber;
    startAmount: BigNumber;
    endAmount: BigNumber;
    recipient: string;
}

export interface OpenseaOfferItem {
    itemType: OpenseaItemType;
    token: string;
    identifierOrCriteria: BigNumber;
    startAmount: BigNumber;
    endAmount: BigNumber;
}

export interface OpenseaOrderParams {
    offerer: string;
    zone: string;
    offer: OpenseaOfferItem[];
    consideration: OpenseaConsiderationItem[];
    orderType: OpenseaOrderType;
    startTime: BigNumber;
    endTime: BigNumber;
    zoneHash: string;
    salt: BigNumber;
    conduitKey: string;
    totalOriginalConsiderationItems: BigNumber;
}

export interface OpenseaAdditionalRecipient {
    amount: BigNumber;
    recipient: string;
}

export interface OpenseaBasicOrderParams {
    considerationToken: string;
    considerationIdentifier: BigNumber;
    considerationAmount: BigNumber;
    offerer: string;
    zone: string;
    offerToken: string;
    offerIdentifier: BigNumber;
    offerAmount: BigNumber;
    basicOrderType: OpenseaBasicOrderType;
    startTime: BigNumber;
    endTime: BigNumber;
    zoneHash: string;
    salt: BigNumber;
    offererConduitKey: string;
    fulfillerConduitKey: string;
    totalOriginalAdditionalRecipients: BigNumber;
    additionalRecipients: OpenseaAdditionalRecipient[];
    signature: string;
}
