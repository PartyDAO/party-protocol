// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

contract PartyBid is IPartyBidV1, Implementation, PartyCrowdfund {
    struct Split {
        address recipient;
        uint16 splitBps;
    }

    struct PartyBidOptions {
        uint256 tokenId;
        uint256 auctionId;
        IMarketWrapper marketWrapper;
        IERC721 nftContract;
        Split split;
        uint32 duratiomInSeconds;
        string name;
        string symbol;
        bytes32 partyOptionsHash;
    }

    // ...

    constructor(IGlobals globals) PartyCrowdfund(globals) { }

    function initialize(bytes calldata rawInitOpts) external onlyDelegateCall {
        PartyBidOptions memory opts = abi.decode(rawInitOpts, (PartyBidOptions));
        PartyCrowdfund._initialize(opts.name, opts.symbol, opts.partyOptionsHash);
        // ...
    }
    // ...
}