// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../tokens/IERC721.sol";

import "./opensea/SharedWyvernV2Maker.sol";
import "./ListOnZoraProposal.sol";
import "./LibProposal.sol";

// Implements arbitrary call proposals.
contract ListOnOpenSeaProposal is ListOnZoraProposal {
    enum OpenSeaStep {
        None,
        ListedOnZora,
        RetrievedFromZora,
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
        // Expiration timestamp of the listing.
        uint40 expiry;
    }

    // Shared OS/Wyvern maker contract for all parties.
    // This allows all parties to avoid having to create a new transfer proxy
    // when listing on opensea for the first time.
    SharedWyvernV2Maker public immutable SHARED_WYVERN_MAKER;

    constructor(SharedWyvernV2Maker sharedMaker) {
        SHARED_WYVERN_MAKER = sharedMaker;
    }

    // Try to create a listing (ultimately) on OpenSea.
    // Creates a listing on Zora AH for list price first. When that ends,
    // calling this function again will list in on OpenSea. When that ends,
    // calling this function again will cancel the listing.
    function _executeListOnOpenSea(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    )
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
            // Unanimous vote. Advance pas the zora phase.
            step = OpenSeaStep.RetrievedFromZora;
        }
        if (step == OpenSeaStep.ListedOnZora) {
            (ZoraProgressData memory zpd) =
                abi.decode(params.progressData, (ZoraProgressData));
            if (zpd.minExpiry < uint40(block.timstamp)) {
                revert ZoraListingNotExpired(zpd.auctionId, zpd.minExpiry);
            }
            // Remove it from zora.
            if (_settleZoraAuction(zpd.auctionId)) {
                // Auction sold. Nothing left to do.
                return "";
            }
            // No bids. Move on.
            step = OpenSeaStep.RetrievedFromZora;
        }
        if (step == OpenSeaStep.RetrievedFromZora) {
            // Either a unanimous vote or retrieved from zora (no bids).
            uint256 expiry = block.timestamp + uint256(data.durationInSeconds);
            bytes32 orderHash = _listOnOpenSea(
                data,
                params.preciousToken,
                params.preciousTokenId,
                expiry
            );
            return abi.encode(OpenSeaStep.ListedOnOpenSea, orderHash, expiry);
        }
        // Already listed on OS.
        assert(step == OpenSeaStep.ListedOnOpenSea);
        (OpenSeaProgressData memory opd) =
            abi.decode(params.progressData, (OpenSeaProgressData));
        _cleanUpListing(
            data,
            params.preciousToken,
            params.preciousTokenId,
            opd
        );
        // Nothing left to do.
        return "";
    }

    function _listOnOpenSea(
        OpenSeaProposalData memory data,
        IERC721 token,
        uint256 tokenId,
        uint256 expiry
    )
        private
        returns (bytes32 orderHash)
    {
        // The shared maker requires us to transfer in the NFT being sold
        // first.
        token.transfer(address(SHARED_WYVERN_MAKER), tokenId);
        orderHash = SHARED_WYVERN_MAKER.createListing(
            token,
            tokenId,
            data.listPrice,
            expiry
        );
    }

    function _cleanUpListing(
        OpenSeaProposalData memory data,
        IERC721 token,
        uint256 tokenId,
        OpenSeaProgressData memory pd
    )
        private
    {
        // This will transfer ETH to us if the listing was bought
        // or transfer the NFT back to us if the listing expired.
        SHARED_WYVERN_MAKER.finalizeListing(
            pd.orderHash,
            token,
            tokenId,
            data.listPrice,
            pd.expiry
        );
    }
}
