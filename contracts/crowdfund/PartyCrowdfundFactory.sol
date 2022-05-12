// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../globals/IGlobals.sol";

import "./PartyBid.sol";
import "./PartyBuy.sol";
import "./PartyCollectionBuy.sol";
import "./PartyCrowdfundProxy.sol";

contract PartyCrowdfundFactory {
    event PartyBuyCreated(PartyBuy.PartyBuyOptions opts);
    event PartyBidCreated(PartyBid.PartyBidOptions opts);
    event PartyCollectionBuyCreated(PartyCollectionBuy.PartyCollectionBuyOptions opts);

    IGlobals private immutable _GLOBALS;
    uint256 private immutable _PARTY_BUY_IMPL_GLOBAL_KEY;
    uint256 private immutable _PARTY_BID_IMPL_GLOBAL_KEY;
    uint256 private immutable _PARTY_COLLECTION_BUY_IMPL_GLOBAL_KEY;

    constructor(
        IGlobals globals,
        uint256 partyBuyImplGlobalKey,
        uint256 partyBidImplGlobalKey,
        uint256 partyCollectionBuyImplGlobalKey
    ) {
        _GLOBALS = globals;
        _PARTY_BUY_IMPL_GLOBAL_KEY = partyBuyImplGlobalKey;
        _PARTY_BID_IMPL_GLOBAL_KEY = partyBidImplGlobalKey;
        _PARTY_COLLECTION_BUY_IMPL_GLOBAL_KEY = partyCollectionBuyImplGlobalKey;
    }

    function createPartyBuy(PartyBuy.PartyBuyOptions calldata opts)
        external
        returns (PartyBuy inst)
    {
        inst = new PartyCrowdfundProxy(
            _GLOBALS,
            _PARTY_BUY_IMPL_GLOBAL_KEY,
            abi.encode(opts)
        );
        emit PartyBuyCreated(opts);
    }

    function createPartyBid(PartyBid.PartyBidOptions calldata opts)
        external
        returns (PartyBid inst)
    {
        inst = new PartyCrowdfundProxy(
            _GLOBALS,
            _PARTY_BID_IMPL_GLOBAL_KEY,
            abi.encode(opts)
        );
        emit PartyBidCreated(opts);
    }

    function createPartyCollectionBuy(
        PartyCollectionBuy.PartyCollectionBuyOptions calldata opts
    )
        external
        returns (PartyBuy inst)
    {
        inst = new PartyCrowdfundProxy(
            _GLOBALS,
            _PARTY_COLLECTION_BUY_IMPL_GLOBAL_KEY,
            abi.encode(opts)
        );
        emit PartyCollectionBuyCreated(opts);
    }
}
