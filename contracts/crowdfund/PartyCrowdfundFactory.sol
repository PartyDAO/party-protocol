// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../globals/IGlobals.sol";
import "../utils/LibRawResult.sol";
import "../utils/Proxy.sol";

import "./PartyBid.sol";
import "./PartyBuy.sol";
import "./PartyCollectionBuy.sol";

contract PartyCrowdfundFactory {
    using LibRawResult for bytes;

    event PartyBuyCreated(PartyBuy.PartyBuyOptions opts);
    event PartyBidCreated(PartyBid.PartyBidOptions opts);
    event PartyCollectionBuyCreated(PartyCollectionBuy.PartyCollectionBuyOptions opts);

    IGlobals private immutable _GLOBALS;

    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    function createPartyBuy(
        PartyBuy.PartyBuyOptions memory opts,
        bytes memory createGateCallData
    )
        public
        payable
        returns (PartyBuy inst)
    {
        opts.gateKeeperId = _prepareGate(
            opts.gateKeeper,
            opts.gateKeeperId,
            createGateCallData
        );
        inst = PartyBuy(payable(new Proxy{ value: msg.value }(
            _GLOBALS.getImplementation(LibGlobals.GLOBAL_PARTY_BUY_IMPL),
            abi.encodeCall(PartyBuy.initialize, (opts))
        )));
        emit PartyBuyCreated(opts);
    }

    function createPartyBid(
        PartyBid.PartyBidOptions memory opts,
        bytes memory createGateCallData
    )
        public
        payable
        returns (PartyBid inst)
    {
        opts.gateKeeperId = _prepareGate(
            opts.gateKeeper,
            opts.gateKeeperId,
            createGateCallData
        );
        inst = PartyBid(payable(new Proxy{ value: msg.value }(
            _GLOBALS.getImplementation(LibGlobals.GLOBAL_PARTY_BID_IMPL),
            abi.encodeCall(PartyBid.initialize, (opts))
        )));
        emit PartyBidCreated(opts);
    }

    function createPartyCollectionBuy(
        PartyCollectionBuy.PartyCollectionBuyOptions memory opts,
        bytes memory createGateCallData
    )
        public
        payable
        returns (PartyCollectionBuy inst)
    {
        opts.gateKeeperId = _prepareGate(
            opts.gateKeeper,
            opts.gateKeeperId,
            createGateCallData
        );
        inst = PartyCollectionBuy(payable(new Proxy{ value: msg.value }(
            _GLOBALS.getImplementation(LibGlobals.GLOBAL_PARTY_COLLECTION_BUY_IMPL),
            abi.encodeCall(PartyCollectionBuy.initialize, (opts))
        )));
        emit PartyCollectionBuyCreated(opts);
    }

    function _prepareGate(
        IGateKeeper gateKeeper,
        bytes12 gateKeeperId,
        bytes memory createGateCallData
    )
        private
        returns (bytes12 newGateKeeperId)
    {
        if (
            address(gateKeeper) == address(0) ||
            gateKeeperId != bytes12(0)
        ) {
            // Using an existing gate on the gatekeeper
            // or not using a gate at all.
            return gateKeeperId;
        }
        // Call the gate creation function on the gatekeeper.
        (bool s, bytes memory r) = address(gateKeeper).call(createGateCallData);
        if (!s) {
            r.rawRevert();
        }
        // Result is always a bytes12.
        return abi.decode(r, (bytes12));
    }
}
