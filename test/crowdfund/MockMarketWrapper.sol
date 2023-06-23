// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/market-wrapper/IMarketWrapper.sol";
import "../../contracts/tokens/IERC20.sol";
import "../../contracts/tokens/IERC721.sol";
import "../../contracts/utils/LibRawResult.sol";

import "../DummyERC721.sol";

contract MockMarketWrapper is IMarketWrapper, Test {
    using LibRawResult for bytes;

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

    event MockMarketWrapperBid(address bidder, uint256 auctionId, uint256 bidAmount);

    event MockMarketWrapperFinalize(address caller, address winner, uint256 topBid);

    uint256[1024] __padding;

    DummyERC721 public nftContract = new DummyERC721();
    mapping(uint256 => MockAuction) _auctionByAuctionId;
    address immutable _impl;
    uint256 _lastAuctionId = 8000;
    address callbackTarget;
    bytes callbackData;
    uint256 callbackValue;

    modifier onlyDelegateCall() {
        require(address(this) != _impl, "ONLY_DELEGATECALL");
        _;
    }

    constructor() {
        _impl = address(this);
    }

    function setCallback(
        address callbackTarget_,
        bytes memory callbackData_,
        uint256 callbackValue_
    ) external {
        callbackTarget = callbackTarget_;
        callbackData = callbackData_;
        callbackValue = callbackValue_;
    }

    function createAuction(uint256 minBid) external returns (uint256 auctionId, uint256 tokenId) {
        tokenId = nftContract.mint(address(this));
        auctionId = ++_lastAuctionId;
        _auctionByAuctionId[auctionId] = MockAuction({
            tokenId: tokenId,
            topBid: minBid,
            winner: payable(0),
            state: AuctionState.Active
        });
    }

    function bid(uint256 auctionId, address payable bidder) external payable {
        _executeCallback();
        MockAuction storage auc = _auctionByAuctionId[auctionId];
        require(auc.state == AuctionState.Active, "AUCTION_NOT_ACTIVE");
        uint256 topBid = auc.topBid;
        require(msg.value >= getMinimumBid(auctionId), "BID_TOO_LOW");
        address payable lastBidder = auc.winner;
        auc.winner = bidder;
        auc.topBid = msg.value;
        if (lastBidder != address(0)) {
            lastBidder.transfer(topBid);
        }
        emit MockMarketWrapperBid(bidder, auctionId, msg.value);
    }

    function cancelAuction(uint256 auctionId) external {
        MockAuction storage auc = _auctionByAuctionId[auctionId];
        require(auc.state == AuctionState.Active, "AUCTION_NOT_ACTIVE");
        auc.state = AuctionState.Cancelled;
    }

    function endAuction(uint256 auctionId) external {
        MockAuction storage auc = _auctionByAuctionId[auctionId];
        require(auc.state == AuctionState.Active, "AUCTION_NOT_ACTIVE");
        auc.state = AuctionState.Ended;
    }

    function auctionIdMatchesToken(
        uint256 auctionId,
        address nftContract_,
        uint256 tokenId
    ) external view returns (bool) {
        MockAuction storage auc = _auctionByAuctionId[auctionId];
        return
            auc.tokenId == tokenId &&
            IERC721(nftContract_) == nftContract &&
            auc.state == AuctionState.Active;
    }

    function getMinimumBid(uint256 auctionId) public view returns (uint256) {
        MockAuction storage auc = _auctionByAuctionId[auctionId];
        if (auc.winner == address(0)) {
            return auc.topBid;
        }
        return auc.topBid + 1;
    }

    function getCurrentHighestBidder(uint256 auctionId) external view returns (address) {
        return _auctionByAuctionId[auctionId].winner;
    }

    function isFinalized(uint256 auctionId) external view returns (bool) {
        MockAuction storage auc = _auctionByAuctionId[auctionId];
        if (auc.tokenId == 0) {
            return true;
        }
        return _auctionByAuctionId[auctionId].state == AuctionState.Finalized;
    }

    function bid(uint256 auctionId, uint256 bidAmount) external onlyDelegateCall {
        MockMarketWrapper(_impl).bid{ value: bidAmount }(auctionId, payable(address(this)));
    }

    function finalize(uint256 auctionId) external {
        _executeCallback();
        MockAuction storage auc = _auctionByAuctionId[auctionId];
        AuctionState state = auc.state;
        require(
            state == AuctionState.Ended || state == AuctionState.Cancelled,
            "AUCTION_NOT_ENDED"
        );
        auc.state = state = AuctionState.Finalized;
        if (auc.winner != address(0)) {
            if (state == AuctionState.Cancelled) {
                auc.winner.transfer(auc.topBid);
            } else {
                // Ended
                nftContract.safeTransferFrom(address(this), auc.winner, auc.tokenId, "");
            }
        }
        emit MockMarketWrapperFinalize(msg.sender, auc.winner, auc.topBid);
    }

    function _executeCallback() private {
        if (callbackTarget != address(0)) {
            (bool s, bytes memory r) = callbackTarget.call{ value: callbackValue }(callbackData);
            if (!s) {
                r.rawRevert();
            }
        }
    }
}
