// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "../globals/IGlobals.sol";
import "../utils/LibRawResult.sol";
import "../utils/Proxy.sol";
import "../renderers/RendererStorage.sol";

import "./AuctionCrowdfund.sol";
import "./BuyCrowdfund.sol";
import "./CollectionBuyCrowdfund.sol";
import "./RollingAuctionCrowdfund.sol";
import "./CollectionBatchBuyCrowdfund.sol";
import "./InitialETHCrowdfund.sol";
import "./ReraiseETHCrowdfund.sol";

/// @notice Factory used to deploys new proxified `Crowdfund` instances.
contract CrowdfundFactory {
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
    ) public payable returns (BuyCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);
        inst = BuyCrowdfund(
            payable(
                new Proxy{ value: msg.value }(
                    Implementation(address(crowdfundImpl)),
                    abi.encodeCall(BuyCrowdfund.initialize, (opts))
                )
            )
        );
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
    ) public payable returns (AuctionCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);
        inst = AuctionCrowdfund(
            payable(
                new Proxy{ value: msg.value }(
                    Implementation(address(crowdfundImpl)),
                    abi.encodeCall(AuctionCrowdfund.initialize, (opts))
                )
            )
        );
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
    ) public payable returns (RollingAuctionCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);
        inst = RollingAuctionCrowdfund(
            payable(
                new Proxy{ value: msg.value }(
                    Implementation(address(crowdfundImpl)),
                    abi.encodeCall(
                        RollingAuctionCrowdfund.initialize,
                        (opts, allowedAuctionsMerkleRoot)
                    )
                )
            )
        );
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
    ) public payable returns (CollectionBuyCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);
        inst = CollectionBuyCrowdfund(
            payable(
                new Proxy{ value: msg.value }(
                    Implementation(address(crowdfundImpl)),
                    abi.encodeCall(CollectionBuyCrowdfund.initialize, (opts))
                )
            )
        );
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
    ) public payable returns (CollectionBatchBuyCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);
        inst = CollectionBatchBuyCrowdfund(
            payable(
                new Proxy{ value: msg.value }(
                    Implementation(address(crowdfundImpl)),
                    abi.encodeCall(CollectionBatchBuyCrowdfund.initialize, (opts))
                )
            )
        );
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
    ) public payable returns (InitialETHCrowdfund inst) {
        crowdfundOpts.gateKeeperId = _prepareGate(
            crowdfundOpts.gateKeeper,
            crowdfundOpts.gateKeeperId,
            createGateCallData
        );
        inst = InitialETHCrowdfund(
            payable(
                new Proxy{ value: msg.value }(
                    Implementation(address(crowdfundImpl)),
                    abi.encodeCall(InitialETHCrowdfund.initialize, (crowdfundOpts, partyOpts))
                )
            )
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
    ) public payable returns (ReraiseETHCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);
        inst = ReraiseETHCrowdfund(
            payable(
                new Proxy{ value: msg.value }(
                    Implementation(address(crowdfundImpl)),
                    abi.encodeCall(ReraiseETHCrowdfund.initialize, (opts))
                )
            )
        );
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
