// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../utils/Implementation.sol";
import "../utils/Proxy.sol";
import "../globals/IGlobals.sol";

// This is what gets deployed when creating a PartyBid/PartyBuy
// `implGlobalKey` should be either:
// - `LibGlobals.GLOBAL_PARTY_BID_IMPL`
// - `LibGlobals.GLOBAL_PARTY_BUY_IMPL`
// - `LibGlobals.GLOBAL_PARTY_COLLECTION_BUY_IMPL`
contract PartyCrowdfundProxy is Proxy {
    constructor(
        IGlobals globals,
        uint256 implGlobalKey,
        bytes memory initData
    )
        payable
        Proxy(Implementation(globals.getAddress(implGlobalKey)), initData)
    {}
}
