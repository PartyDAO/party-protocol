// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Implements arbitrary call proposals.
contract ListOnOpenSeaProposal is EIP1271Callback, ListOnZoraProposal {
    enum OpenSeaStep {
        None,
        ListedOnZora,
        ZoraListingFailed,
        ListedOnOpenSea
    }

    // ABI-encoded `proposalData` passed into execute.
    struct OpenSeaProposalData {
        uint256 listPrice;
        uint40 durationInSeconds;
    }

    // ABI-encoded `progressData` passed into execute in the `ListedOnOpenSea` step.
    struct OpenSeaProgressData {
        // Hash of the OS order that was listed.
        bytes32 orderHash;
        // Expiration timestamp of the offer.
        uint40 expiry;
    }

    // Useful for discovery?
    event OpenSeaOrderListed(OpenSeaOrder order);

    error OpenSeaListingNotExpired(bytes32 orderHash, uint40 expiry);

    IGlobals private immutable GLOBALS;

    constructor(IGblobals globals) {
        GLOBALS = globals;
    }

    // Try to create a listing (ultimately) on OpenSea.
    // Creates a listing on Zora AH for list price first. When that ends,
    // calling this function again will list in on OpenSea. When that ends,
    // calling this function again will cancel the listing.
    function _executeListOnOpenSea(ExecuteProposalParams memory params)
        internal
        returns (bytes memory nextProgressData)
    {
        (OpenSeaProposalData memory data) = abi.decode(params.proposalData, (OpenSeaProposalData));
        bool isUnanimous = params.flags & LibProposal.PROPOSAL_FLAG_UNANIMOUS
            == LibProposal.PROPOSAL_FLAG_UNANIMOUS;
        (OpenSeaStep step) = abi.decode(params.progressData, (OpenSeaStep));
        if (step == OpenSeaStep.None) {
            // Proposal hasn't executed yet.
            if (!isUnanimous) {
                // Not a unanimous vote so list on zora first.
                (uint256 auctionId, uint40 minExpiry) = _createZoraAuction(
                    data.listPrice,
                    params.preciousToken,
                    params.preciousTokenId
                );
                return abi.encode(OpenSeaStep.ListedOnZora, ZoraProgressData({
                    auctionId: auctionId,
                    minExpiry: minExpiry
                }));
            }
            step = OpenSeaStep.RetrievedFromZora;
        }
        if (step == OpenSeaStep.ListedOnZora) {
            (ZoraProgressData memory pd) =
                abi.decode(params.progressData, (ZoraProgressData));
            if (pd.minExpiry < uint40(block.timstamp)) {
                revert ZoraListingNotExpired(pd.auctionId, pd.minExpiry);
            }
            // Remove it from zora.
            if (_settleZoraAuction(pd.auctionId)) {
                // Auction sold. Nothing left to do.
                return "";
            }
            // No bids. Move on.
            step = OpenSeaStep.ZoraListingFailed;
        }
        if (step == OpenSeaStep.ZoraListingFailed) {
            // Either a unanimous vote or retrieved from zora (no bids).
            bytes32 orderHash = _listOnOpenSea(
                data,
                params.preciousToken,
                params.preciousTokenId
            );
            return abi.encode(OpenSeaStep.ListedOnOpenSea, OpenSeaProgressData(orderHash));
        }
        // Already listed on OS.
        assert(step == OpenSeaStep.ListedOnOpenSea);
        (OpenSeaProgressData memory pd) =
            abi.decode(params.progressData, (OpenSeaProgressData));
        if (pd.expiry < uint40(block.timestamp)) {
            revert OpenSeaListingNotExpired(pd.orderHash, pd.expiry);
        }
        _cancelOpenSeaListing(pd.orderHash);
        // Nothing left to do.
        return "";
    }

    function _listOnOpenSea(OpenSeaProposalData memory data, IERC721 token, uint256 tokenId)
        private
        returns (bytes32 orderHash)
    {
        // ...
        OpenSeaOrder order = ...;
        orderHash = _getOpenSeaOrderHash(order);
        _setValidEIP1271Hash(orderHash);
        emit OpenSeaOrderListed(order);
    }

    function _cancelOpenSeaListing(bytes32 orderHash)
        private
    {
        // TODO: openSea.cancelOrder(orderHash) ??
        _setValidEIP1271Hash(bytes32(0));
    }
}
