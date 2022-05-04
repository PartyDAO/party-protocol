// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// The Party instance. Just a thin proxy that delegatecalls into previously deployed
// implementation logic.
contract PartyProxy is Proxy {
    constructor(bytes calldata initData)
        Proxy(
            IPartyFactory(msg.sender)
                .GLOBALS()
                .getAddress(LibGlobals.GLOBAL_PARTY_IMPL),
            initData
        )
    {}
}
