// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../tokens/IERC721.sol";

// Abstract Zora interaction functions.
// Used by both `ListOnZoraProposal` and `ListOnOpenseaProposal`.
abstract contract ZoraHelpers {
    // ABI-encoded `progressData` passed into execute in the `ListedOnZora` step.
    struct ZoraProgressData {
        // Auction ID.
        uint256 auctionId;
        // The minimum timestamp when we can cancel the auction if no one bids.
        uint40 minExpiry;
    }

    enum ZoraAuctionStatus {
        Sold,
        Expired,
        Cancelled
    }

    // Transfer and create a Zora auction for the token + tokenId.
    function _createZoraAuction(
        // The minimum bid.
        uint256 listPrice,
        // How long the auction must wait for the first bid.
        uint40 timeout,
        // How long the auction will run for once a bid has been placed.
        uint40 duration,
        IERC721 token,
        uint256 tokenId
    ) internal virtual returns (uint256 auctionId);

    // Either cancel or finalize a Zora auction.
    function _settleZoraAuction(
        uint256 auctionId,
        uint40 minExpiry,
        IERC721 token,
        uint256 tokenId
    ) internal virtual returns (ZoraAuctionStatus statusCode);
}
