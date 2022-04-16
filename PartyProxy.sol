// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// What gets deployed by PartyFactory when creating a new Party.
contract PartyProxy is Proxy {
    constructor(bytes calldata initData)
        Proxy(IPartyFactory(msg.sender).GLOBALS().getAddress(PARTY_IMPL), initData)
    {}
}