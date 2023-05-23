// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// ============ External Imports ============
import { INounsBuilderAuctionHouse } from "../vendor/markets/INounsBuilderAuctionHouse.sol";

// ============ Internal Imports ============
import { IMarketWrapper } from "./IMarketWrapper.sol";
import "../tokens/IERC721.sol";

/**
 * @title NounsBuilderMarketWrapper
 * @author Yiwen Gao
 * @notice MarketWrapper contract implementing IMarketWrapper interface
 * according to the logic of Zora's Nouns Builder Auction House
 * Nouns Builder Auction House code: https://github.com/ourzora/nouns-protocol/blob/main/src/auction/Auction.sol 
 * 
 * Nouns Builder auctions are similar to Nouns auctions, but some function signatures differ, 
 * so a new market wrapper is needed to account for them 
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

    // ======== Constructor =========

    constructor(address _auctionHouse) {
        market = INounsBuilderAuctionHouse(_auctionHouse);
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
     * @notice Determine whether there is an existing, active auction for this token. 
     * In the Nouns Builder auction house, the current auction id is the token id, which increments sequentially, forever 
     * @return TRUE if the auction exists
     */
    function auctionExists(uint256 tokenId, AuctionState memory state) public view returns (bool) {
        return tokenId == state.tokenId && block.timestamp < state.endTime;
    }

    /**
     * @notice Determine whether the current auction is valid
     * @return TRUE if the tokenId matches the current token for sale, and the auction is neither settled nor paused
     */
    function auctionIdMatchesToken(
        uint256 auctionId,
        address nftContract,
        uint256 tokenId
    ) public view override returns (bool) {
        AuctionState memory state = _getAuctionState();
        return (
            auctionId == tokenId
            && auctionExists(tokenId, state)
            && market.token() == IERC721(nftContract)
        );
    }

    /**
     * @notice Calculate the minimum next bid for this auction
     * @return minimum bid amount
     */
    function getMinimumBid(uint256 tokenId) external view override returns (uint256) {
        AuctionState memory state = _getAuctionState();
        require(
            auctionExists(tokenId, state), 
            "NounsBuilderMarketWrapper::getMinimumBid: Auction not active"
        );

        if (state.highestBidder == address(0)) {
            // if there are NO bids, the minimum bid is the reserve price
            return market.reservePrice();
        } else {
            // if there ARE bids, the minimum bid is the current bid plus the increment buffer
            return state.highestBid + (state.highestBid * market.minBidIncrement() / 100);
        }
    }

    /**
     * @notice Query the current highest bidder for this auction
     * @return highest bidder
     */
    function getCurrentHighestBidder(uint256 tokenId) external view override returns (address) {
        AuctionState memory state = _getAuctionState();
        require(
            auctionExists(tokenId, state), 
            "NounsBuilderMarketWrapper::getCurrentHighestBidder: Auction not active"
        );
        return state.highestBidder;
    }

    /**
     * @notice Submit bid to Market contract
     */
    function bid(uint256 tokenId, uint256 bidAmount) external override {
        AuctionState memory state = _getAuctionState();
        require(
            auctionExists(tokenId, state), 
            "NounsBuilderMarketWrapper::bid: Auction not active"
        );
        market.createBid{ value: bidAmount }(state.tokenId);
    }

    /**
     * @notice Determine whether the auction has been finalized
     * @return TRUE if the auction has been finalized
     */
    function isFinalized(uint256 tokenId) external view override returns (bool) {
        AuctionState memory state = _getAuctionState();
        // if the given token id isn't the current token id, then it's for a past token
        // and the corresponding auction must've been settled already
        return tokenId != state.tokenId || state.settled;
    }

    /**
     * @notice Finalize the results of the auction
     * Parameter auctionId is unused because there's at most one ongoing auction for Nouns Builder DAOs
     */
    function finalize(uint256) external override {
        if (market.paused()) {
            market.settleAuction();
        } else {
            market.settleCurrentAndCreateNewAuction();
        }
    }
}
