// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../globals/IGlobals.sol";
import "../utils/LibRawResult.sol";
import "../utils/Proxy.sol";
import "../utils/LibENS.sol";
import "../renderers/RendererStorage.sol";

import "./AuctionCrowdfund.sol";
import "./BuyCrowdfund.sol";
import "./CollectionBuyCrowdfund.sol";

/// @notice Factory used to deploys new proxified `Crowdfund` instances.
contract CrowdfundFactory {
    using LibRawResult for bytes;

    event BuyCrowdfundCreated(BuyCrowdfund crowdfund, BuyCrowdfund.BuyCrowdfundOptions opts);
    event AuctionCrowdfundCreated(
        AuctionCrowdfund crowdfund,
        AuctionCrowdfund.AuctionCrowdfundOptions opts
    );
    event CollectionBuyCrowdfundCreated(
        CollectionBuyCrowdfund crowdfund,
        CollectionBuyCrowdfund.CollectionBuyCrowdfundOptions opts
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
    ///
    ///             IMPORTANT: If using a custom ENS domain (aka. not a
    ///             "partybid.eth" subdomain) for the crowdfund, the owner MUST
    ///             authorize the crowdfund to be able to edit the domain's
    ///             records so that it can update the address record to the new
    ///             party after it wins. This can be done by calling
    ///             `setAuthorisation()` on the ENS public resolver at:
    ///             0x4976fb03C32e5B8cfe2b6cCB31c09Ba78EBaBa41.
    /// @param createGateCallData Encoded calldata used by `createGate()` to
    ///                           create the crowdfund if one is specified in `opts`.
    function createBuyCrowdfund(
        BuyCrowdfund.BuyCrowdfundOptions memory opts,
        bytes memory createGateCallData
    ) public payable returns (BuyCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);

        // Create a "partybid.eth" subdomain for the crowdfund if specified.
        bytes32 subdomainNode;
        if (LibENS.isPartyBidSubdomain(opts.ens.node)) {
            subdomainNode = LibENS.createSubdomain(opts.ens.label, address(this));
        }

        inst = BuyCrowdfund(
            payable(
                new Proxy{ value: msg.value }(
                    _GLOBALS.getImplementation(LibGlobals.GLOBAL_BUY_CF_IMPL),
                    abi.encodeCall(BuyCrowdfund.initialize, (opts))
                )
            )
        );

        // Finish configuring subdomain if newly created.
        if (subdomainNode != bytes32(0)) {
            LibENS.setAddress(subdomainNode, address(inst));
            LibENS.setAuthorization(subdomainNode, address(inst), true);
        }

        emit BuyCrowdfundCreated(inst, opts);
    }

    /// @notice Create a new crowdfund to bid on an auction for a specific NFT
    ///         (i.e. with a known token ID).
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    ///
    ///             IMPORTANT: If using a custom ENS domain (aka. not a
    ///             "partybid.eth" subdomain) for the crowdfund, the owner MUST
    ///             authorize the crowdfund to be able to edit the domain's
    ///             records so that it can update the address record to the new
    ///             party after it wins. This can be done by calling
    ///             `setAuthorisation()` on the ENS public resolver at:
    ///             0x4976fb03C32e5B8cfe2b6cCB31c09Ba78EBaBa41.
    /// @param createGateCallData Encoded calldata used by `createGate()` to create
    ///                           the crowdfund if one is specified in `opts`.
    function createAuctionCrowdfund(
        AuctionCrowdfund.AuctionCrowdfundOptions memory opts,
        bytes memory createGateCallData
    ) public payable returns (AuctionCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);

        // Create a "partybid.eth" subdomain for the crowdfund if specified.
        bytes32 subdomainNode;
        if (LibENS.isPartyBidSubdomain(opts.ens.node)) {
            subdomainNode = LibENS.createSubdomain(opts.ens.label, address(this));
        }

        inst = AuctionCrowdfund(
            payable(
                new Proxy{ value: msg.value }(
                    _GLOBALS.getImplementation(LibGlobals.GLOBAL_AUCTION_CF_IMPL),
                    abi.encodeCall(AuctionCrowdfund.initialize, (opts))
                )
            )
        );

        // Finish configuring subdomain if newly created.
        if (subdomainNode != bytes32(0)) {
            LibENS.setAddress(subdomainNode, address(inst));
            LibENS.setAuthorization(subdomainNode, address(inst), true);
        }

        emit AuctionCrowdfundCreated(inst, opts);
    }

    /// @notice Create a new crowdfund to purchase any NFT from a collection
    ///         (i.e. any token ID) from a collection for a known price.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    ///
    ///             IMPORTANT: If using a custom ENS domain (aka. not a
    ///             "partybid.eth" subdomain) for the crowdfund, the owner MUST
    ///             authorize the crowdfund to be able to edit the domain's
    ///             records so that it can update the address record to the new
    ///             party after it wins. This can be done by calling
    ///             `setAuthorisation()` on the ENS public resolver at:
    ///             0x4976fb03C32e5B8cfe2b6cCB31c09Ba78EBaBa41.
    /// @param createGateCallData Encoded calldata used by `createGate()` to create
    ///                           the crowdfund if one is specified in `opts`.
    function createCollectionBuyCrowdfund(
        CollectionBuyCrowdfund.CollectionBuyCrowdfundOptions memory opts,
        bytes memory createGateCallData
    ) public payable returns (CollectionBuyCrowdfund inst) {
        opts.gateKeeperId = _prepareGate(opts.gateKeeper, opts.gateKeeperId, createGateCallData);

        // Create a "partybid.eth" subdomain for the crowdfund if specified.
        bytes32 subdomainNode;
        if (LibENS.isPartyBidSubdomain(opts.ens.node)) {
            subdomainNode = LibENS.createSubdomain(opts.ens.label, address(this));
        }

        inst = CollectionBuyCrowdfund(
            payable(
                new Proxy{ value: msg.value }(
                    _GLOBALS.getImplementation(LibGlobals.GLOBAL_COLLECTION_BUY_CF_IMPL),
                    abi.encodeCall(CollectionBuyCrowdfund.initialize, (opts))
                )
            )
        );

        // Finish configuring subdomain if newly created.
        if (subdomainNode != bytes32(0)) {
            LibENS.setAddress(subdomainNode, address(inst));
            LibENS.setAuthorization(subdomainNode, address(inst), true);
        }

        emit CollectionBuyCrowdfundCreated(inst, opts);
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
