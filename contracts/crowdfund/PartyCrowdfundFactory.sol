// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

contract PartyCrowdfundFactory {
    event PartyBuyCreated(PartyBuy.PartyBuyOptions opts);
    event PartyBidCreated(PartyBid.PartyBidOptions opts);

    IGlobals private immutable _GLOBALS;
    uint256 private immutable _PARTY_BUY_GLOBAL_KEY;
    uint256 private immutable _PARTY_BID_GLOBAL_KEY;

    constructor(
        IGlobals globals,
        uint256 partyBuyGlobalKey,
        uint256 partyBidGlobalKey
    ) {
        _GLOBALS = globals;
        partyBuyGlobalKey = _PARTY_BUY_GLOBAL_KEY;
        partyBidGlobalKey = _PARTY_BID_GLOBAL_KEY;
    }

    function createPartyBuy(PartyBuy.PartyBuyOptions calldata opts)
        external
        returns (PartyBuy inst)
    {
        inst = new PartyCrowdfundProxy(_GLOBALS, _PARTY_BUY_GLOBAL_KEY, abi.encode(opts));
        emit PartyBuyCreated(opts);
    }

    function createPartyBid(PartyBid.PartyBidOptions calldata opts)
        external
        returns (PartyBid inst)
    {
        inst = new PartyCrowdfundProxy(_GLOBALS, _PARTY_BID_GLOBAL_KEY, abi.encode(opts));
        emit PartyBidCreated(opts);
    }
}
