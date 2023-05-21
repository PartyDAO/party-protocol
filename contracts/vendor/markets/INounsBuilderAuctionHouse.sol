// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../../tokens/IERC721.sol";

/**
 * Nouns Builder auctions are similar to Nouns auctions, but some function signatures differ, 
 * so a new auction house is needed to account for them 
 */
interface INounsBuilderAuctionHouse {
    function createBid(uint256 tokenId) external payable;

    function auction() external view returns (
        uint256 tokenId, 
        uint256 highestBid, 
        address highestBidder, 
        uint40 startTime, 
        uint40 endTime, 
        bool settled
    );

    function token() external view returns (IERC721);

    function reservePrice() external view returns (uint256);

    function minBidIncrement() external view returns (uint256);

    function settleAuction() external;

    function settleCurrentAndCreateNewAuction() external;

    function paused() external view returns (bool);
}
