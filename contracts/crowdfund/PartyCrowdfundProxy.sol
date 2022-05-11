// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../utils/Proxy.sol";

// This is what gets deployed when creating a PartyBid/PartyBuy
// `implGlobalKey` should be either:
// - `LibGobals.GLOBAL_PARTY_BID_IMPL`
// - `LibGobals.GLOBAL_PARTY_BUY_IMPL`
// - `LibGobals.GLOBAL_PARTY_COLLECTION_BUY_IMPL`
contract PartyCrowdfundProxy is Proxy {
    constructor(
        IGlobals globals,
        uint256 implGlobalKey,
        bytes memory initData
    )
        payable
        Proxy(globals.getAddress(implGlobalKey), initData)
    {}
}
