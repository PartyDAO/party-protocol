// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { Clones } from "openzeppelin/contracts/proxy/Clones.sol";

import { LibRawResult } from "../utils/LibRawResult.sol";
import { IGateKeeper } from "../gatekeepers/IGateKeeper.sol";

import { AuctionCrowdfund, AuctionCrowdfundBase } from "./AuctionCrowdfund.sol";
import { BuyCrowdfund } from "./BuyCrowdfund.sol";
import { CollectionBuyCrowdfund } from "./CollectionBuyCrowdfund.sol";
import { RollingAuctionCrowdfund } from "./RollingAuctionCrowdfund.sol";
import { CollectionBatchBuyCrowdfund } from "./CollectionBatchBuyCrowdfund.sol";
import { InitialETHCrowdfund, ETHCrowdfundBase } from "./InitialETHCrowdfund.sol";
import { ReraiseETHCrowdfund } from "./ReraiseETHCrowdfund.sol";
import { MetadataProvider } from "../renderers/MetadataProvider.sol";
import { Party } from "../party/Party.sol";

/// @notice Factory used to deploys new proxified `Crowdfund` instances.
contract CrowdfundFactory {
    using Clones for address;
    using LibRawResult for bytes;

    event BuyCrowdfundCreated(
        address indexed creator,
        BuyCrowdfund indexed crowdfund,
        BuyCrowdfund.BuyCrowdfundOptions opts
    );
    event AuctionCrowdfundCreated(
        address indexed creator,
        AuctionCrowdfund indexed crowdfund,
        AuctionCrowdfundBase.AuctionCrowdfundOptions opts
    );
    event CollectionBuyCrowdfundCreated(
        address indexed creator,
        CollectionBuyCrowdfund indexed crowdfund,
        CollectionBuyCrowdfund.CollectionBuyCrowdfundOptions opts
    );
    event RollingAuctionCrowdfundCreated(
        address indexed creator,
        RollingAuctionCrowdfund indexed crowdfund,
        AuctionCrowdfundBase.AuctionCrowdfundOptions opts,
        bytes32 allowedAuctionsMerkleRoot
    );
    event CollectionBatchBuyCrowdfundCreated(
        address indexed creator,
        CollectionBatchBuyCrowdfund indexed crowdfund,
        CollectionBatchBuyCrowdfund.CollectionBatchBuyCrowdfundOptions opts
    );
    event InitialETHCrowdfundCreated(
        address indexed creator,
        InitialETHCrowdfund indexed crowdfund,
        Party indexed party,
        InitialETHCrowdfund.InitialETHCrowdfundOptions crowdfundOpts,
        InitialETHCrowdfund.ETHPartyOptions partyOpts
    );
    event ReraiseETHCrowdfundCreated(
        address indexed creator,
        ReraiseETHCrowdfund indexed crowdfund,
        ETHCrowdfundBase.ETHCrowdfundOptions opts
    );

    /// @notice Create a new crowdfund to purchase a specific NFT (i.e., with a
    ///         known token ID) listing for a known price.
    /// @param crowdfundImpl The implementation contract of the crowdfund to create.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    /// @param createGateCallData Encoded calldata used by `createGate()` to
    ///                           create the crowdfund if one is specified in `opts`.
    function createBuyCrowdfund(
        BuyCrowdfund crowdfundImpl,
        BuyCrowdfund.BuyCrowdfundOptions memory opts,
        bytes memory createGateCallData
    ) external payable returns (BuyCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);
        inst = BuyCrowdfund(address(crowdfundImpl).clone());
        inst.initialize{ value: msg.value }(opts);
        emit BuyCrowdfundCreated(msg.sender, inst, opts);
    }

    /// @notice Create a new crowdfund to bid on an auction for a specific NFT
    ///         (i.e. with a known token ID).
    /// @param crowdfundImpl The implementation contract of the crowdfund to create.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    /// @param createGateCallData Encoded calldata used by `createGate()` to create
    ///                           the crowdfund if one is specified in `opts`.
    function createAuctionCrowdfund(
        AuctionCrowdfund crowdfundImpl,
        AuctionCrowdfundBase.AuctionCrowdfundOptions memory opts,
        bytes memory createGateCallData
    ) external payable returns (AuctionCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);
        inst = AuctionCrowdfund(payable(address(crowdfundImpl).clone()));
        inst.initialize{ value: msg.value }(opts);
        emit AuctionCrowdfundCreated(msg.sender, inst, opts);
    }

    /// @notice Create a new crowdfund to bid on an auctions for an NFT from a collection
    ///         on a market (e.g. Nouns).
    /// @param crowdfundImpl The implementation contract of the crowdfund to create.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    /// @param createGateCallData Encoded calldata used by `createGate()` to create
    ///                           the crowdfund if one is specified in `opts`.
    function createRollingAuctionCrowdfund(
        RollingAuctionCrowdfund crowdfundImpl,
        AuctionCrowdfundBase.AuctionCrowdfundOptions memory opts,
        bytes32 allowedAuctionsMerkleRoot,
        bytes memory createGateCallData
    ) external payable returns (RollingAuctionCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);
        inst = RollingAuctionCrowdfund(payable(address(crowdfundImpl).clone()));
        inst.initialize{ value: msg.value }(opts, allowedAuctionsMerkleRoot);
        emit RollingAuctionCrowdfundCreated(msg.sender, inst, opts, allowedAuctionsMerkleRoot);
    }

    /// @notice Create a new crowdfund to purchases any NFT from a collection
    ///         (i.e. any token ID) from a collection for a known price.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    /// @param createGateCallData Encoded calldata used by `createGate()` to create
    ///                           the crowdfund if one is specified in `opts`.
    function createCollectionBuyCrowdfund(
        CollectionBuyCrowdfund crowdfundImpl,
        CollectionBuyCrowdfund.CollectionBuyCrowdfundOptions memory opts,
        bytes memory createGateCallData
    ) external payable returns (CollectionBuyCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);
        inst = CollectionBuyCrowdfund(address(crowdfundImpl).clone());
        inst.initialize{ value: msg.value }(opts);
        emit CollectionBuyCrowdfundCreated(msg.sender, inst, opts);
    }

    /// @notice Create a new crowdfund to purchase multiple NFTs from a collection
    ///         (i.e. any token ID) from a collection for known prices.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    /// @param createGateCallData Encoded calldata used by `createGate()` to create
    ///                           the crowdfund if one is specified in `opts`.
    function createCollectionBatchBuyCrowdfund(
        CollectionBatchBuyCrowdfund crowdfundImpl,
        CollectionBatchBuyCrowdfund.CollectionBatchBuyCrowdfundOptions memory opts,
        bytes memory createGateCallData
    ) external payable returns (CollectionBatchBuyCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);
        inst = CollectionBatchBuyCrowdfund(address(crowdfundImpl).clone());
        inst.initialize{ value: msg.value }(opts);
        emit CollectionBatchBuyCrowdfundCreated(msg.sender, inst, opts);
    }

    /// @notice Create a new crowdfund to raise ETH for a new party.
    /// @param crowdfundImpl The implementation contract of the crowdfund to create.
    /// @param crowdfundOpts Options used to initialize the crowdfund. These are fixed
    ///                      and cannot be changed later.
    /// @param partyOpts Options used to initialize the party created by the crowdfund.
    ///                  These are fixed and cannot be changed later.
    /// @param createGateCallData Encoded calldata used by `createGate()` to create
    ///                           the crowdfund if one is specified in `opts`.
    function createInitialETHCrowdfund(
        InitialETHCrowdfund crowdfundImpl,
        InitialETHCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts,
        InitialETHCrowdfund.ETHPartyOptions memory partyOpts,
        bytes memory createGateCallData
    ) external payable returns (InitialETHCrowdfund inst) {
        return
            createInitialETHCrowdfundWithMetadata(
                crowdfundImpl,
                crowdfundOpts,
                partyOpts,
                MetadataProvider(address(0)),
                "",
                createGateCallData
            );
    }

    /// @notice Create a new crowdfund to raise ETH for a new party.
    /// @param crowdfundImpl The implementation contract of the crowdfund to create.
    /// @param crowdfundOpts Options used to initialize the crowdfund.
    /// @param partyOpts Options used to initialize the party created by the crowdfund.
    /// @param customMetadataProvider A custom metadata provider to use for the party.
    /// @param customMetadata Custom metadata to use for the party.
    /// @param createGateCallData Encoded calldata used by `createGate()` to create
    ///                           the crowdfund if one is specified in `opts`.
    function createInitialETHCrowdfundWithMetadata(
        InitialETHCrowdfund crowdfundImpl,
        InitialETHCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts,
        InitialETHCrowdfund.ETHPartyOptions memory partyOpts,
        MetadataProvider customMetadataProvider,
        bytes memory customMetadata,
        bytes memory createGateCallData
    ) public payable returns (InitialETHCrowdfund inst) {
        crowdfundOpts.gateKeeperId = _prepareGate(
            crowdfundOpts.gateKeeper,
            crowdfundOpts.gateKeeperId,
            createGateCallData
        );
        inst = InitialETHCrowdfund(address(crowdfundImpl).clone());
        inst.initialize{ value: msg.value }(
            crowdfundOpts,
            partyOpts,
            customMetadataProvider,
            customMetadata
        );
        emit InitialETHCrowdfundCreated(msg.sender, inst, inst.party(), crowdfundOpts, partyOpts);
    }

    /// @notice Create a new crowdfund to raise ETH for an existing party.
    /// @param crowdfundImpl The implementation contract of the crowdfund to create.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    /// @param createGateCallData Encoded calldata used by `createGate()` to create
    ///                           the crowdfund if one is specified in `opts`.
    function createReraiseETHCrowdfund(
        ReraiseETHCrowdfund crowdfundImpl,
        ETHCrowdfundBase.ETHCrowdfundOptions memory opts,
        bytes memory createGateCallData
    ) external payable returns (ReraiseETHCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);
        inst = ReraiseETHCrowdfund(address(crowdfundImpl).clone());
        inst.initialize{ value: msg.value }(opts);
        emit ReraiseETHCrowdfundCreated(msg.sender, inst, opts);
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
