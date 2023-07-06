// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @title IReserveAuctionCoreEth
/// @author kulkarohan
/// @notice Interface for Reserve Auction Core ETH
interface IReserveAuctionCoreEth {
    /// @notice Creates an auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _duration The length of time the auction should run after the first bid
    /// @param _reservePrice The minimum bid amount to start the auction
    /// @param _sellerFundsRecipient The address to send funds to once the auction is complete
    /// @param _startTime The time that users can begin placing bids
    function createAuction(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _duration,
        uint256 _reservePrice,
        address _sellerFundsRecipient,
        uint256 _startTime
    ) external;

    /// @notice Updates the auction reserve price for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _reservePrice The new reserve price
    function setAuctionReservePrice(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _reservePrice
    ) external;

    /// @notice Cancels the auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function cancelAuction(address _tokenContract, uint256 _tokenId) external;

    /// @notice Places a bid on the auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function createBid(address _tokenContract, uint256 _tokenId) external payable;

    /// @notice Ends the auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function settleAuction(address _tokenContract, uint256 _tokenId) external;

    function auctionForNFT(
        address _tokenContract,
        uint256 _tokenId
    ) external view returns (Auction calldata);

    function erc721TransferHelper() external pure returns (BaseTransferHelper);

    /// @notice The metadata for a given auction
    /// @param seller The address of the seller
    /// @param reservePrice The reserve price to start the auction
    /// @param sellerFundsRecipient The address where funds are sent after the auction
    /// @param highestBid The highest bid of the auction
    /// @param highestBidder The address of the highest bidder
    /// @param duration The length of time that the auction runs after the first bid is placed
    /// @param startTime The time that the first bid can be placed
    /// @param firstBidTime The time that the first bid is placed
    struct Auction {
        address seller;
        uint96 reservePrice;
        address sellerFundsRecipient;
        uint96 highestBid;
        address highestBidder;
        uint32 duration;
        uint32 startTime;
        uint32 firstBidTime;
    }
}

interface ZoraModuleManager {
    function setApprovalForModule(address, bool) external;
}

interface BaseTransferHelper {
    function ZMM() external returns (ZoraModuleManager);
}
