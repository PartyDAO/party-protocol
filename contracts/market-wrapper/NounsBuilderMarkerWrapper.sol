// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// ============ External Imports ============
import { INounsBuilderAuctionHouse } from "../vendor/markets/INounsBuilderAuctionHouse.sol";

// ============ Internal Imports ============
import { IMarketWrapper } from "./IMarketWrapper.sol";
import "../tokens/IERC721.sol";
import "../tokens/IERC20.sol";

/**
 * @title NounsBuilderMarketWrapper
 * @author Yiwen Gao
 * @notice MarketWrapper contract implementing IMarketWrapper interface
 * according to the logic of Zora's Nouns Builder Auction House
 * Original Nouns Builder Auction House code: https://github.com/ourzora/nouns-protocol/blob/main/src/auction/Auction.sol 
 */
contract NounsBuilderMarketWrapper is IMarketWrapper {
    struct AuctionState {
        uint256 tokenId;
        uint256 highestBid;
        address highestBidder;
        uint40 startTime;
        uint40 endTime;
        bool settled;
    }

    // ============ Internal Immutables ============

    INounsBuilderAuctionHouse internal immutable market;
    uint256 internal immutable reservePrice;
    uint256 internal immutable minBidIncrement;

    // ======== Constructor =========

    constructor(address _auctionHouse) {
        market = INounsBuilderAuctionHouse(_auctionHouse);
        reservePrice = market.reservePrice();
        minBidIncrement = market.minBidIncrement();
    }

    // ======== Private Functions =========

    /**
     * @notice Retrieve the state for the current auction
     */
    function _getAuctionState() private view returns (AuctionState memory) {
        (
            uint256 tokenId,
            uint256 highestBid,
            address highestBidder,
            uint40 startTime,
            uint40 endTime,
            bool settled
        ) = market.auction();
        return AuctionState(tokenId, highestBid, highestBidder, startTime, endTime, settled);
    }

    // ======== External Functions =========

    /**
     * @notice Determine whether the current auction is valid
     * Parameters auctionId and nftContract are unused because there's at most one ongoing auction for Nouns Builder DAOs
     * @return TRUE if the tokenId matches the current token for sale, and the auction is neither settled nor paused
     */
    function auctionIdMatchesToken(
        uint256, // auctionId
        address, // nftContract
        uint256 tokenId
    ) public view override returns (bool) {
        AuctionState memory state = _getAuctionState();
        return (
            state.tokenId == tokenId
            && !state.settled
            && !market.paused() 
        );
    }

    /**
     * @notice Calculate the minimum next bid for this auction
     * Parameter auctionId is unused because there's at most one ongoing auction for Nouns Builder DAOs
     * @return minimum bid amount
     */
    function getMinimumBid(uint256) external view override returns (uint256) {
        AuctionState memory state = _getAuctionState();
        if (state.highestBidder == address(0)) {
            // if there are NO bids, the minimum bid is the reserve price
            return reservePrice;
        } else {
            // if there ARE bids, the minimum bid is the current bid plus the increment buffer
            return state.highestBid + (state.highestBid * minBidIncrement / 100);
        }
    }

    /**
     * @notice Query the current highest bidder for this auction
     * Parameter auctionId is unused because there's at most one ongoing auction for Nouns Builder DAOs
     * @return highest bidder
     */
    function getCurrentHighestBidder(uint256) external view override returns (address) {
        AuctionState memory state = _getAuctionState();
        return state.highestBidder;
    }

    /**
     * @notice Submit bid to Market contract
     * Parameter auctionId is unused because there's at most one ongoing auction for Nouns Builder DAOs
     */
    function bid(uint256, uint256 bidAmount) external override {
        AuctionState memory state = _getAuctionState();
        market.createBid{ value: bidAmount }(state.tokenId);
    }

    /**
     * @notice Determine whether the auction has been finalized
     * Parameter auctionId is unused because there's at most one ongoing auction for Nouns Builder DAOs
     * @return TRUE if the auction has been finalized
     */
    function isFinalized(uint256) external view override returns (bool) {
        AuctionState memory state = _getAuctionState();
        return state.settled;
    }

    /**
     * @notice Finalize the results of the auction
     * Parameter auctionId is unused because there's at most one ongoing auction for Nouns Builder DAOs
     */
    function finalize(uint256) external override {
        market.settleAuction();
    }
}
