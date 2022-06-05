// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/IMarketWrapper.sol";
import "../../contracts/tokens/IERC721.sol";

import "../DummyERC721.sol";


contract MockMarketWrapper is IMarketWrapper, Test {
    enum AuctionState {
        Inactive,
        Active,
        Ended,
        Cancelled,
        Finalized
    }

    struct MockAuction {
        uint256 tokenId;
        uint256 topBid;
        address payable winner;
        AuctionState state;
    }

    DummyERC721 public nftContract = new DummyERC721();
    mapping (uint256 => MockAuction) _auctionByAuctionId;
    address immutable _impl;
    uint256 _lastAuctionId = 8000;

    modifier onlyDelegateCall() {
        require(address(this) != _impl, 'ONLY_DELEGATECALL');
        _;
    }

    constructor() {
        _impl = address(this);
    }

    function createAuction(uint256 minBid)
        external
        returns (uint256 auctionId, uint256 tokenId)
    {
        tokenId = nftContract.mint(address(this));
        auctionId = ++_lastAuctionId;
        _auctionByAuctionId[auctionId] = MockAuction({
            tokenId: tokenId,
            topBid: minBid,
            winner: payable(0),
            state: AuctionState.Active
        });
    }

    function mockBid(uint256 auctionId, address payable bidder, uint256 bidAmount)
        payable
        external
    {
        MockAuction storage auc = _auctionByAuctionId[auctionId];
        require(auc.state == AuctionState.Active, 'AUCTION_NOT_ACTIVE');
        uint256 topBid = auc.topBid;
        require(bidAmount >= getMinimumBid(auctionId), 'BID_TOO_LOW');
        address payable lastBidder = auc.winner;
        auc.winner = bidder;
        auc.topBid = bidAmount;
        if (lastBidder != address(0)) {
            lastBidder.transfer(topBid);
        }
    }

    function mockCancelAuction(uint256 auctionId)
        external
    {
        MockAuction storage auc = _auctionByAuctionId[auctionId];
        require(auc.state == AuctionState.Active, 'AUCTION_NOT_ACTIVE');
        auc.state = AuctionState.Cancelled;
    }

    function mockEndAuction(uint256 auctionId)
        external
    {
        MockAuction storage auc = _auctionByAuctionId[auctionId];
        require(auc.state == AuctionState.Active, 'AUCTION_NOT_ACTIVE');
        auc.state = AuctionState.Ended;
    }

    function auctionIdMatchesToken(
        uint256 auctionId,
        address nftContract_,
        uint256 tokenId
    )
        external
        view
        returns (bool)
    {
        MockAuction storage auc = _auctionByAuctionId[auctionId];
        return auc.tokenId == tokenId && IERC721(nftContract_) == nftContract;
    }

    function getMinimumBid(uint256 auctionId) public view returns (uint256) {
        MockAuction storage auc = _auctionByAuctionId[auctionId];
        if (auc.winner == address(0)) {
            return auc.topBid;
        }
        return auc.topBid + 1;
    }

    function getCurrentHighestBidder(uint256 auctionId)
        external
        view
        returns (address)
    {
        return _auctionByAuctionId[auctionId].winner;
    }

    function isFinalized(uint256 auctionId) external view returns (bool) {
        MockAuction storage auc = _auctionByAuctionId[auctionId];
        if (auc.tokenId == 0) {
            return true;
        }
        return _auctionByAuctionId[auctionId].state == AuctionState.Finalized;
    }

    function bid(uint256 auctionId, uint256 bidAmount)
        external
        onlyDelegateCall
    {
        MockMarketWrapper(_impl).mockBid
            { value: bidAmount }
            (auctionId, payable(address(this)), bidAmount);
    }

    function finalize(uint256 auctionId) external {
        MockAuction storage auc = _auctionByAuctionId[auctionId];
        AuctionState state = auc.state;
        require(state == AuctionState.Ended || state == AuctionState.Cancelled, 'AUCTION_NOT_ENDED');
        auc.state = state = AuctionState.Finalized;
        if (auc.winner != address(0)) {
            if (state == AuctionState.Cancelled) {
                auc.winner.transfer(auc.topBid);
            } else { // Ended
                nftContract.transferFrom(address(this), auc.winner, auc.tokenId);
            }
        }
    }
}
