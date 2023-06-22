// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/tokens/IERC20.sol";
import "../../contracts/tokens/IERC721.sol";
import "../../contracts/vendor/markets/IZoraAuctionHouse.sol";

contract MockZoraAuctionHouse is IZoraAuctionHouse {
    uint256 public lastAuctionId = 8000;
    uint256 public timeBuffer = 15 minutes;

    function createAuction(
        uint256,
        IERC721,
        uint256,
        uint256,
        address payable,
        uint8,
        IERC20
    ) external returns (uint256 auctionId) {
        auctionId = ++lastAuctionId;
    }

    function createBid(uint256, uint256) external payable {
        revert("no implementado");
    }

    function endAuction(uint256) external pure {
        revert("no implementado");
    }

    function cancelAuction(uint256) external pure {
        revert("no implementado");
    }

    function auctions(uint256) external pure returns (Auction memory) {
        revert("no implementado");
    }

    function minBidIncrementPercentage() external pure returns (uint8) {
        revert("no implementado");
    }
}
