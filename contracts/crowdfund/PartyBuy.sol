// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

contract PartyBuy is IPartyBuyV1, Implementation, PartyCrowdfund {
    struct Split {
        address recipient;
        uint16 splitBps;
    }

    struct PartyBuyOptions {
        uint256 tokenId;
        IERC721 nftContract;
        uint128 maxPrice;
        uint32 durationInSeconds;
        address payable splitRecipient;
        uint16 splitBps;
        string name;
        string symbol;
        bytes32 partyOptionsHash;
        address initialDelegate;
    }

    // ...

    constructor(IGlobals globals) PartyCrowdfund(globals) { }

    function initialize(bytes calldata rawInitOpts)
        external
        override
        onlyDelegateCall
    {
        PartyBuyOptions memory opts = abi.decode(rawInitOpts, (PartyBuyOptions));
        PartyCrowdfund.initialize(
            opts.name,
            opts.symbol,
            opts.partyOptionsHash,
            opts.splitRecipient,
            opts.splitBps,
            opts.initialDelegate
        );
        // ...
    }

    function _transferSharedAssetsTo(address recipient) internal override {
        nftContract.transfer(recipient, boughtTokenId);
    }

    function _getCrowdfundLifecycle() internal override view returns (CrowdfundLifecycle) {
        // Note: cannot rely on ownerOf because it might be transferred to Party
        // if `createParty()` was called.
        if (boughtTokenId == tokenId) {
            return CrowdfundLifecycle.Won;
        }
        // ...
    }

    function _getFinalContribution(address contributor)
        internal
        override
        view
        returns (uint256 ethUsed, uint256 ethOwed)
    {
        // Loop throough `contributor`'s contributions and return
        // how much was actually used and how much was not.
    }

    // Rest of PartyBuyV1 functions...
}
