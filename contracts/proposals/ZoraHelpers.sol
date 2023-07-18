// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "../tokens/IERC721.sol";

// Abstract Zora interaction functions.
// Used by both `ListOnZoraProposal` and `ListOnOpenseaAdvancedProposal`.
abstract contract ZoraHelpers {
    // ABI-encoded `progressData` passed into execute in the `ListedOnZora` step.
    struct ZoraProgressData {
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
        address token,
        uint256 tokenId
    ) internal virtual;

    // Either cancel or finalize a Zora auction.
    function _settleZoraAuction(
        uint40 minExpiry,
        address token,
        uint256 tokenId
    ) internal virtual returns (ZoraAuctionStatus statusCode);
}
