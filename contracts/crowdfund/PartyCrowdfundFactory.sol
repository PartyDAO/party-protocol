// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../globals/IGlobals.sol";
import "../utils/LibRawResult.sol";
import "../utils/Proxy.sol";

import "./AuctionCrowdfund.sol";
import "./BuyCrowdfund.sol";
import "./CollectionBuyCrowdfund.sol";

/// @notice Factory used to deploys new proxified `PartyCrowdfund` instances.
contract PartyCrowdfundFactory {
    using LibRawResult for bytes;

    event BuyCrowdfundCreated(PartyBuy crowdfund, PartyBuy.PartyBuyOptions opts);
    event AuctionCrowdfundCreated(PartyBid crowdfund, PartyBid.PartyBidOptions opts);
    event CollectionBuyCrowdfundCreated(CollectionBuyCrowdfund crowdfund, PartyCollectionBuy.PartyCollectionBuyOptions opts);

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    // Set the `Globals` contract.
    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    /// @notice Create a new crowdfund to purchases a specific NFT (i.e., with a
    ///         known token ID) listing for a known price.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    /// @param createGateCallData Encoded calldata used by `createGate()` to
    ///                           create the crowdfund if one is specified in `opts`.
    function createBuyCrowdfund(
        BuyCrowdfund.PartyBuyOptions memory opts,
        bytes memory createGateCallData
    )
        public
        payable
        returns (BuyCrowdfund inst)
    {
        opts.gateKeeperId = _prepareGate(
            opts.gateKeeper,
            opts.gateKeeperId,
            createGateCallData
        );
        inst = BuyCrowdfund(payable(new Proxy{ value: msg.value }(
            _GLOBALS.getImplementation(LibGlobals.GLOBAL_PARTY_BUY_IMPL),
            abi.encodeCall(BuyCrowdfund.initialize, (opts))
        )));
        emit BuyCrowdfundCreated(inst, opts);
    }

    /// @notice Create a new crowdfund to bid on an auction for a specific NFT
    ///         (i.e. with a known token ID).
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    /// @param createGateCallData Encoded calldata used by `createGate()` to create
    ///                           the crowdfund if one is specified in `opts`.
    function createAuctionCrowdfund(
        AuctionCrowdfund.PartyBidOptions memory opts,
        bytes memory createGateCallData
    )
        public
        payable
        returns (AuctionCrowdfund inst)
    {
        opts.gateKeeperId = _prepareGate(
            opts.gateKeeper,
            opts.gateKeeperId,
            createGateCallData
        );
        inst = AuctionCrowdfund(payable(new Proxy{ value: msg.value }(
            _GLOBALS.getImplementation(LibGlobals.GLOBAL_PARTY_BID_IMPL),
            abi.encodeCall(AuctionCrowdfund.initialize, (opts))
        )));
        emit AuctionCrowdfundCreated(inst, opts);
    }

    /// @notice Create a new crowdfund to purchases any NFT from a collection
    ///         (i.e. any token ID) from a collection for a known price.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    /// @param createGateCallData Encoded calldata used by `createGate()` to create
    ///                           the crowdfund if one is specified in `opts`.
    function createCollectionBuyCrowdfund(
        CollectionBuyCrowdfund.CollectionBuyCrowdfundOptions memory opts,
        bytes memory createGateCallData
    )
        public
        payable
        returns (CollectionBuyCrowdfund inst)
    {
        opts.gateKeeperId = _prepareGate(
            opts.gateKeeper,
            opts.gateKeeperId,
            createGateCallData
        );
        inst = CollectionBuyCrowdfund(payable(new Proxy{ value: msg.value }(
            _GLOBALS.getImplementation(LibGlobals.GLOBAL_PARTY_COLLECTION_BUY_IMPL),
            abi.encodeCall(CollectionBuyCrowdfund.initialize, (opts))
        )));
        emit CollectionBuyCrowdfundCreated(inst, opts);
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
