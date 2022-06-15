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
        // Expiration timestamp of the auction, if no one bids.
        uint40 minExpiry;
    }

    function _createZoraAuction(
        uint256 listPrice,
        uint40 duration,
        IERC721 token,
        uint256 tokenId
    )
        internal
        virtual
        returns (uint256 auctionId, uint40 minExpiry);


    function _settleZoraAuction(uint256 auctionId, uint40 minExpiry, IERC721 token, uint256 tokenId)
        internal
        virtual
        returns (bool sold);
}
