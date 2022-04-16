// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

contract PartyBuy is IPartyBuyV1, Implementation, PartyCrowdfund {
    struct PartyBuyOptions {
        uint256 tokenId;
        IERC721 nftContract;
        uint128 maxPrice;
        uint32 duratiomInSeconds;
        address splitRecipient;
        uint32 splitBps;
        string name;
        string symbol;
        bytes32 partyOptionsHash;
    }

    // ...

    constructor(IGlobals globals) PartyCrowdfund(globals) { }

    function initialize(bytes calldata rawInitOpts) external onlyDelegateCall {
        PartyBuyOptions memory opts = abi.decode(rawInitOpts, (PartyBuyOptions));
        PartyCrowdfund._initialize(opts.name, opts.symbol, opts.partyOptionsHash);
        // ...
    }
    // ...
}