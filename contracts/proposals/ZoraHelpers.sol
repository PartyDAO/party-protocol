// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../tokens/IERC721.sol";

// Abstract zora interaction functions.
// Implemented by ListOnZoraProposal.
abstract contract ZoraHelpers {

    // ABI-encoded `progressData` passed into execute in the `ListedOnZora` step.
    struct ZoraProgressData {
        // Acution ID.
        uint256 auctionId;
        // The minimum timestamp when we can cancel the auction if no one bids.
        uint40 minExpiry;
    }

    // Transfer and create a zora auction for the token + tokenId.
    function _createZoraAuction(
        // The minimum bid.
        uint256 listPrice,
        // How long the auction must wait for the first bid.
        uint40 timeout,
        // How long the auction will run for once a bid has been placed.
        uint40 duration,
        IERC721 token,
        uint256 tokenId
    )
        internal
        virtual
        returns (uint256 auctionId);

    // Either cancel or finalize a zora auction.
    function _settleZoraAuction(uint256 auctionId, uint40 minExpiry)
        internal
        virtual
        returns (bool sold);
}
