// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// This is what gets deployed when creating a PartyBid/PartyBuy
contract PartyCrowdfundProxy is Proxy {
    constructor(IGlobals globals, uint256 implGlobalId, bytes memory initData)
        Proxy(globals.getAddress(implGlobalId), initData)
    { }
}