// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// ============ External Imports ============
import { IZoraAuctionHouse } from "../vendor/markets/IZoraAuctionHouse.sol";

// ============ Internal Imports ============
import { IMarketWrapper } from "./IMarketWrapper.sol";
import "../tokens/IERC721.sol";
import "../tokens/IERC20.sol";

/**
 * @title ZoraMarketWrapper
 * @author Anna Carroll
 * @notice MarketWrapper contract implementing IMarketWrapper interface
 * according to the logic of Zora's Auction Houses
 * Original Zora Auction House code: https://github.com/ourzora/auction-house/blob/main/contracts/AuctionHouse.sol
 */
contract ZoraMarketWrapper is IMarketWrapper {
    // ============ Internal Immutables ============

    IZoraAuctionHouse internal immutable market;
    uint8 internal immutable minBidIncrementPercentage;

    // ======== Constructor =========

    constructor(address _zoraAuctionHouse) {
        market = IZoraAuctionHouse(_zoraAuctionHouse);
        minBidIncrementPercentage = IZoraAuctionHouse(_zoraAuctionHouse)
            .minBidIncrementPercentage();
    }

    // ======== External Functions =========

    /**
     * @notice Determine whether there is an existing auction
     * for this token on the market
     * @return TRUE if the auction exists
     */
    function auctionExists(uint256 auctionId) public view returns (bool) {
        // line 375 of Zora Auction House, _exists() function (not exposed publicly)
        IZoraAuctionHouse.Auction memory _auction = market.auctions(auctionId);
        return _auction.tokenOwner != address(0);
    }

    /**
     * @notice Determine whether the given auctionId is
     * an auction for the tokenId + nftContract
     * @return TRUE if the auctionId matches the tokenId + nftContract
     */
    function auctionIdMatchesToken(
        uint256 auctionId,
        address nftContract,
        uint256 tokenId
    ) public view override returns (bool) {
        IZoraAuctionHouse.Auction memory _auction = market.auctions(auctionId);
        return
            _auction.tokenId == tokenId &&
            _auction.tokenContract == IERC721(nftContract) &&
            _auction.auctionCurrency == IERC20(address(0));
    }

    /**
     * @notice Calculate the minimum next bid for this auction
     * @return minimum bid amount
     */
    function getMinimumBid(uint256 auctionId) external view override returns (uint256) {
        // line 173 of Zora Auction House, calculation within createBid() function (calculation not exposed publicly)
        IZoraAuctionHouse.Auction memory _auction = market.auctions(auctionId);
        if (_auction.bidder == address(0)) {
            // if there are NO bids, the minimum bid is the reserve price
            return _auction.reservePrice;
        } else {
            // if there ARE bids, the minimum bid is the current bid plus the increment buffer
            return _auction.amount + ((_auction.amount * minBidIncrementPercentage) / 100);
        }
    }

    /**
     * @notice Query the current highest bidder for this auction
     * @return highest bidder
     */
    function getCurrentHighestBidder(uint256 auctionId) external view override returns (address) {
        // line 279 of NFTMarketReserveAuction, getMinBidAmount() function
        IZoraAuctionHouse.Auction memory _auction = market.auctions(auctionId);
        return _auction.bidder;
    }

    /**
     * @notice Submit bid to Market contract
     */
    function bid(uint256 auctionId, uint256 bidAmount) external override {
        // line 153 of Zora Auction House, createBid() function
        (bool success, bytes memory returnData) = address(market).call{ value: bidAmount }(
            abi.encodeWithSignature("createBid(uint256,uint256)", auctionId, bidAmount)
        );
        require(success, string(returnData));
    }

    /**
     * @notice Determine whether the auction has been finalized
     * @return TRUE if the auction has been finalized
     */
    function isFinalized(uint256 auctionId) external view override returns (bool) {
        // line 302 of Zora Auction House,
        // the auction is deleted at the end of the endAuction() function
        // since we checked that the auction DID exist when we deployed the partyBid,
        // if it no longer exists that means the auction has been finalized.
        return !auctionExists(auctionId);
    }

    /**
     * @notice Finalize the results of the auction
     */
    function finalize(uint256 auctionId) external override {
        // line 249 of Zora Auction House, endAuction() function
        market.endAuction(auctionId);
    }
}
