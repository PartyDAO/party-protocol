// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/vendor/markets/IReserveAuctionCoreEth.sol";

contract ZoraTestUtils is Test {
    IReserveAuctionCoreEth private immutable _ZORA;

    constructor(IReserveAuctionCoreEth zora) {
        _ZORA = zora;
    }

    function _bidOnZoraListing(
        address tokenContract,
        uint256 tokenId,
        address bidder,
        uint256 bidPrice
    ) internal {
        hoax(bidder, bidPrice);
        _ZORA.createBid{ value: bidPrice }(tokenContract, tokenId);
    }
}
