// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "contracts/proposals/ListOnZoraProposal.sol";
import "contracts/globals/Globals.sol";
import "../TestUtils.sol";
import "../DummyERC721.sol";
import "./TestableListOnZoraProposal.sol";
import "./ZoraTestUtils.sol";
import { LibSafeCast } from "../../contracts/utils/LibSafeCast.sol";

using LibSafeCast for uint256;

contract ListOnZoraProposalForkedTest is ZoraTestUtils, TestUtils {
    IReserveAuctionCoreEth ZORA =
        IReserveAuctionCoreEth(0x5f7072E1fA7c01dfAc7Cf54289621AFAaD2184d0);
    Globals globals = new Globals(address(this));
    TestableListOnZoraProposal proposal = new TestableListOnZoraProposal(globals, ZORA);
    DummyERC721 nftToken = new DummyERC721();
    uint256 nftTokenId;

    event ZoraAuctionCreated(
        address token,
        uint256 tokenId,
        uint256 startingPrice,
        uint40 duration,
        uint40 timeoutTime
    );
    event ZoraAuctionExpired(address token, uint256 tokenid, uint256 expiry);
    event ZoraAuctionSold(address token, uint256 tokenid);

    // Zora events
    event AuctionCreated(
        address indexed tokenContract,
        uint256 indexed tokenId,
        IReserveAuctionCoreEth.Auction auction
    );
    event AuctionBid(
        address indexed tokenContract,
        uint256 indexed tokenId,
        bool firstBid,
        bool extended,
        IReserveAuctionCoreEth.Auction auction
    );
    event AuctionCanceled(
        address indexed tokenContract,
        uint256 indexed tokenId,
        IReserveAuctionCoreEth.Auction auction
    );
    event AuctionEnded(
        address indexed tokenContract,
        uint256 indexed tokenId,
        IReserveAuctionCoreEth.Auction auction
    );

    constructor() ZoraTestUtils(ZORA) {
        nftTokenId = nftToken.mint(address(proposal));
    }

    function _createExecutionParams()
        private
        view
        returns (
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams,
            ListOnZoraProposal.ZoraProposalData memory proposalData
        )
    {
        proposalData = ListOnZoraProposal.ZoraProposalData({
            listPrice: _randomUint256() % 1e18,
            timeout: uint40(_randomRange(1 hours, 1 days)),
            duration: uint40(_randomRange(1 hours, 1 days)),
            token: address(nftToken),
            tokenId: nftTokenId
        });
        executeParams.proposalData = abi.encode(proposalData);
    }

    function _bidOnListing(address tokenContract, uint256 tokenId, uint256 bid) private {
        _bidOnListing(_randomAddress(), tokenContract, tokenId, bid);
    }

    function _bidOnListing(
        address bidder,
        address tokenContract,
        uint256 tokenId,
        uint256 bid
    ) private {
        IReserveAuctionCoreEth.Auction memory auction = ZORA.auctionForNFT(tokenContract, tokenId);
        uint256 timeBuffer = 15 minutes;
        vm.deal(bidder, bid);
        vm.prank(bidder);

        // cache needed values
        uint32 firstBidTime = auction.firstBidTime;
        auction.highestBidder = bidder;
        auction.highestBid = bid.safeCastUint256ToUint96();
        auction.firstBidTime = uint32(block.timestamp);

        _expectEmit3();
        emit AuctionBid(
            tokenContract,
            tokenId,
            firstBidTime == 0,
            auction.firstBidTime + auction.duration < block.timestamp + timeBuffer,
            auction
        );
        ZORA.createBid{ value: bid }(tokenContract, tokenId);
    }

    function testForked_canCreateListing() external onlyForked {
        (
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams,
            ListOnZoraProposal.ZoraProposalData memory proposalData
        ) = _createExecutionParams();
        // _expectEmit3();
        // emit AuctionCreated(
        //     proposalData.token,
        //     proposalData.tokenId,
        // );
        _expectEmit0();
        emit ZoraAuctionCreated(
            proposalData.token,
            proposalData.tokenId,
            proposalData.listPrice,
            proposalData.duration,
            uint40(block.timestamp + proposalData.timeout)
        );
        assertTrue(proposal.executeListOnZora(executeParams).length > 0);
    }

    function testForked_canBidOnListing() external onlyForked {
        (
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams,
            ListOnZoraProposal.ZoraProposalData memory proposalData
        ) = _createExecutionParams();
        proposal.executeListOnZora(executeParams);
        _bidOnListing(proposalData.token, proposalData.tokenId, proposalData.listPrice);
    }

    function testForked_canCancelExpiredListing() external onlyForked {
        (
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams,
            ListOnZoraProposal.ZoraProposalData memory proposalData
        ) = _createExecutionParams();
        executeParams.progressData = proposal.executeListOnZora(executeParams);
        skip(proposalData.timeout);
        // _expectEmit3();
        // emit AuctionCanceled(
        //     proposalData.token,
        //     proposalData.tokenId
        // );
        _expectEmit0();
        emit ZoraAuctionExpired(proposalData.token, proposalData.tokenId, block.timestamp);
        assertTrue(proposal.executeListOnZora(executeParams).length == 0);
    }

    function testForked_cannotCancelUnexpiredListing() external onlyForked {
        (
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams,
            ListOnZoraProposal.ZoraProposalData memory proposalData
        ) = _createExecutionParams();
        executeParams.progressData = proposal.executeListOnZora(executeParams);
        skip(proposalData.timeout - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ListOnZoraProposal.ZoraListingNotExpired.selector,
                proposalData.token,
                proposalData.tokenId,
                block.timestamp + 1
            )
        );
        proposal.executeListOnZora(executeParams);
    }

    function testForked_cannotSettleOngoingListing() external onlyForked {
        (
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams,
            ListOnZoraProposal.ZoraProposalData memory proposalData
        ) = _createExecutionParams();
        executeParams.progressData = proposal.executeListOnZora(executeParams);
        _bidOnListing(proposalData.token, proposalData.tokenId, proposalData.listPrice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ListOnZoraProposal.ZoraListingLive.selector,
                proposalData.token,
                proposalData.tokenId,
                block.timestamp + proposalData.duration
            )
        );
        proposal.executeListOnZora(executeParams);
    }

    function testForked_canSettleSuccessfulListing() external onlyForked {
        (
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams,
            ListOnZoraProposal.ZoraProposalData memory proposalData
        ) = _createExecutionParams();
        executeParams.progressData = proposal.executeListOnZora(executeParams);
        _bidOnListing(proposalData.token, proposalData.tokenId, proposalData.listPrice);
        skip(proposalData.duration);
        _expectEmit0();
        emit ZoraAuctionSold(proposalData.token, proposalData.tokenId);
        assertTrue(proposal.executeListOnZora(executeParams).length == 0);
        assertEq(address(proposal).balance, proposalData.listPrice);
    }

    function testForked_canSettleSuccessfulEndedListing() external onlyForked {
        (
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams,
            ListOnZoraProposal.ZoraProposalData memory proposalData
        ) = _createExecutionParams();
        executeParams.progressData = proposal.executeListOnZora(executeParams);
        _bidOnListing(proposalData.token, proposalData.tokenId, proposalData.listPrice);
        skip(proposalData.duration);
        ZORA.settleAuction(proposalData.token, proposalData.tokenId);
        _expectEmit0();
        emit ZoraAuctionSold(proposalData.token, proposalData.tokenId);
        assertTrue(proposal.executeListOnZora(executeParams).length == 0);
        assertEq(address(proposal).balance, proposalData.listPrice);
    }
}

contract BadBidder {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        revert("nope");
    }
}
