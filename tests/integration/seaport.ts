import { BigNumber } from 'ethers';

export enum SeaportItemType {
    NATIVE                    = 0,
    ERC20                     = 1,
    ERC721                    = 2,
    ERC1155                   = 3,
    ERC721_WITH_CRITERIA      = 4,
    ERC1155_WITH_CRITERIA     = 5,
}

export enum SeaportBasicOrderType {
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

export enum SeaportOrderType {
    FULL_OPEN          = 0,
    PARTIAL_OPEN       = 1,
    FULL_RESTRICTED    = 2,
    PARTIAL_RESTRICTED = 3,
}

export interface SeaportConsiderationItem {
    itemType: SeaportItemType;
    token: string;
    identifierOrCriteria: BigNumber;
    startAmount: BigNumber;
    endAmount: BigNumber;
    recipient: string;
}

export interface SeaportOfferItem {
    itemType: SeaportItemType;
    token: string;
    identifierOrCriteria: BigNumber;
    startAmount: BigNumber;
    endAmount: BigNumber;
}

export interface SeaportOrderParams {
    offerer: string;
    zone: string;
    offer: SeaportOfferItem[];
    consideration: SeaportConsiderationItem[];
    orderType: SeaportOrderType;
    startTime: BigNumber;
    endTime: BigNumber;
    zoneHash: string;
    salt: BigNumber;
    conduitKey: string;
    totalOriginalConsiderationItems: BigNumber;
}

export interface SeaportAdditionalRecipient {
    amount: BigNumber;
    recipient: string;
}

export interface SeaportBasicOrderParams {
    considerationToken: string;
    considerationIdentifier: BigNumber;
    considerationAmount: BigNumber;
    offerer: string;
    zone: string;
    offerToken: string;
    offerIdentifier: BigNumber;
    offerAmount: BigNumber;
    basicOrderType: SeaportBasicOrderType;
    startTime: BigNumber;
    endTime: BigNumber;
    zoneHash: string;
    salt: BigNumber;
    offererConduitKey: string;
    fulfillerConduitKey: string;
    totalOriginalAdditionalRecipients: BigNumber;
    additionalRecipients: SeaportAdditionalRecipient[];
    signature: string;
}
