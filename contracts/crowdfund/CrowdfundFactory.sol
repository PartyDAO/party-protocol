// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../globals/IGlobals.sol";
import "../utils/LibRawResult.sol";
import "../utils/Proxy.sol";
import "../renderers/RendererStorage.sol";

import "./AuctionCrowdfund.sol";
import "./BuyCrowdfund.sol";
import "./CollectionBuyCrowdfund.sol";
import "./RollingAuctionCrowdfund.sol";
import "./CollectionBatchBuyCrowdfund.sol";

/// @notice Factory used to deploys new proxified `Crowdfund` instances.
contract CrowdfundFactory {
    using LibRawResult for bytes;

    event BuyCrowdfundCreated(BuyCrowdfund crowdfund, BuyCrowdfund.BuyCrowdfundOptions opts);
    event AuctionCrowdfundCreated(
        AuctionCrowdfund crowdfund,
        AuctionCrowdfundBase.AuctionCrowdfundOptions opts
    );
    event CollectionBuyCrowdfundCreated(
        CollectionBuyCrowdfund crowdfund,
        CollectionBuyCrowdfund.CollectionBuyCrowdfundOptions opts
    );
    event RollingAuctionCrowdfundCreated(
        RollingAuctionCrowdfund crowdfund,
        RollingAuctionCrowdfund.RollingAuctionCrowdfundOptions opts
    );
    event CollectionBatchBuyCrowdfundCreated(
        CollectionBatchBuyCrowdfund crowdfund,
        CollectionBatchBuyCrowdfund.CollectionBatchBuyCrowdfundOptions opts
    );

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    // Set the `Globals` contract.
    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    /// @notice Create a new crowdfund to purchase a specific NFT (i.e., with a
    ///         known token ID) listing for a known price.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    /// @param createGateCallData Encoded calldata used by `createGate()` to
    ///                           create the crowdfund if one is specified in `opts`.
    function createBuyCrowdfund(
        BuyCrowdfund.BuyCrowdfundOptions memory opts,
        bytes memory createGateCallData
    ) public payable returns (BuyCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);
        inst = BuyCrowdfund(
            payable(
                new Proxy{ value: msg.value }(
                    _GLOBALS.getImplementation(LibGlobals.GLOBAL_BUY_CF_IMPL),
                    abi.encodeCall(BuyCrowdfund.initialize, (opts))
                )
            )
        );
        emit BuyCrowdfundCreated(inst, opts);
    }

    /// @notice Create a new crowdfund to bid on an auction for a specific NFT
    ///         (i.e. with a known token ID).
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    /// @param createGateCallData Encoded calldata used by `createGate()` to create
    ///                           the crowdfund if one is specified in `opts`.
    function createAuctionCrowdfund(
        AuctionCrowdfundBase.AuctionCrowdfundOptions memory opts,
        bytes memory createGateCallData
    ) public payable returns (AuctionCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);
        inst = AuctionCrowdfund(
            payable(
                new Proxy{ value: msg.value }(
                    _GLOBALS.getImplementation(LibGlobals.GLOBAL_AUCTION_CF_IMPL),
                    abi.encodeCall(AuctionCrowdfund.initialize, (opts))
                )
            )
        );
        emit AuctionCrowdfundCreated(inst, opts);
    }

    /// @notice Create a new crowdfund to bid on an auctions for an NFT from a collection
    ///         on a market (eg. Nouns).
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    /// @param createGateCallData Encoded calldata used by `createGate()` to create
    ///                           the crowdfund if one is specified in `opts`.
    function createRollingAuctionCrowdfund(
        RollingAuctionCrowdfund.RollingAuctionCrowdfundOptions memory opts,
        bytes memory createGateCallData
    ) public payable returns (RollingAuctionCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);
        inst = RollingAuctionCrowdfund(
            payable(
                new Proxy{ value: msg.value }(
                    _GLOBALS.getImplementation(LibGlobals.GLOBAL_ROLLING_AUCTION_CF_IMPL),
                    abi.encodeCall(RollingAuctionCrowdfund.initialize, (opts))
                )
            )
        );
        emit RollingAuctionCrowdfundCreated(inst, opts);
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
    ) public payable returns (CollectionBuyCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);
        inst = CollectionBuyCrowdfund(
            payable(
                new Proxy{ value: msg.value }(
                    _GLOBALS.getImplementation(LibGlobals.GLOBAL_COLLECTION_BUY_CF_IMPL),
                    abi.encodeCall(CollectionBuyCrowdfund.initialize, (opts))
                )
            )
        );
        emit CollectionBuyCrowdfundCreated(inst, opts);
    }

    /// @notice Create a new crowdfund to purchase multiple NFTs from a collection
    ///         (i.e. any token ID) from a collection for known prices.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    /// @param createGateCallData Encoded calldata used by `createGate()` to create
    ///                           the crowdfund if one is specified in `opts`.
    function createCollectionBatchBuyCrowdfund(
        CollectionBatchBuyCrowdfund.CollectionBatchBuyCrowdfundOptions memory opts,
        bytes memory createGateCallData
    ) public payable returns (CollectionBatchBuyCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);
        inst = CollectionBatchBuyCrowdfund(
            payable(
                new Proxy{ value: msg.value }(
                    _GLOBALS.getImplementation(LibGlobals.GLOBAL_COLLECTION_BATCH_BUY_CF_IMPL),
                    abi.encodeCall(CollectionBatchBuyCrowdfund.initialize, (opts))
                )
            )
        );
        emit CollectionBatchBuyCrowdfundCreated(inst, opts);
    }

    function _prepareGate(
        IGateKeeper gateKeeper,
        bytes12 gateKeeperId,
        bytes memory createGateCallData
    ) private returns (bytes12 newGateKeeperId) {
        if (address(gateKeeper) == address(0) || gateKeeperId != bytes12(0)) {
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
