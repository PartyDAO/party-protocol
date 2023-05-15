// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../../tokens/IERC721.sol";
import "../../tokens/IERC20.sol";

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

    function reservePrice() external view returns (uint256);

    function minBidIncrement() external view returns (uint256);

    function settleAuction() external;

    function settleCurrentAndCreateNewAuction() external;

    function paused() external view returns (bool);
}
