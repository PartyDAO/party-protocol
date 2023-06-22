// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "contracts/proposals/ListOnZoraProposal.sol";
import "contracts/globals/Globals.sol";
import "../TestUtils.sol";
import "../DummyERC721.sol";
import "./TestableListOnZoraProposal.sol";
import "./ZoraTestUtils.sol";

contract ListOnZoraProposalForkedTest is ZoraTestUtils, TestUtils {
    IZoraAuctionHouse ZORA = IZoraAuctionHouse(0xE468cE99444174Bd3bBBEd09209577d25D1ad673);
    Globals globals = new Globals(address(this));
    TestableListOnZoraProposal proposal = new TestableListOnZoraProposal(globals, ZORA);
    DummyERC721 nftToken = new DummyERC721();
    uint256 nftTokenId;

    event ZoraAuctionCreated(
        uint256 auctionId,
        IERC721 token,
        uint256 tokenId,
        uint256 startingPrice,
        uint40 duration,
        uint40 timeoutTime
    );
    event ZoraAuctionExpired(uint256 auctionId, uint256 expiry);
    event ZoraAuctionSold(uint256 auctionId);
    event ZoraAuctionFailed(uint256 auctionId);

    // Zora events
    event AuctionCreated(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed tokenContract,
        uint256 duration,
        uint256 reservePrice,
        address tokenOwner,
        address curator,
        uint8 curatorFeePercentage,
        address auctionCurrency
    );
    event AuctionBid(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed tokenContract,
        address sender,
        uint256 value,
        bool firstBid,
        bool extended
    );
    event AuctionCanceled(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed tokenContract,
        address tokenOwner
    );
    event AuctionEnded(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed tokenContract,
        address tokenOwner,
        address curator,
        address winner,
        uint256 amount,
        uint256 curatorFee,
        address auctionCurrency
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
            token: nftToken,
            tokenId: nftTokenId
        });
        executeParams.proposalData = abi.encode(proposalData);
    }

    function _bidOnListing(uint256 auctionId, uint256 bid) private {
        _bidOnListing(_randomAddress(), auctionId, bid);
    }

    function _bidOnListing(address bidder, uint256 auctionId, uint256 bid) private {
        IZoraAuctionHouse.Auction memory auction = ZORA.auctions(auctionId);
        uint256 timeBuffer = ZORA.timeBuffer();
        vm.deal(bidder, bid);
        vm.prank(bidder);
        _expectEmit3();
        emit AuctionBid(
            auctionId,
            auction.tokenId,
            address(auction.tokenContract),
            bidder,
            bid,
            auction.firstBidTime == 0,
            block.timestamp - auction.firstBidTime - auction.duration <= timeBuffer
        );
        ZORA.createBid{ value: bid }(auctionId, bid);
    }

    function testForked_canCreateListing() external onlyForked {
        (
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams,
            ListOnZoraProposal.ZoraProposalData memory proposalData
        ) = _createExecutionParams();
        uint256 auctionId = _getNextZoraAuctionId();
        _expectEmit3();
        emit AuctionCreated(
            auctionId,
            proposalData.tokenId,
            address(proposalData.token),
            proposalData.duration,
            proposalData.listPrice,
            address(proposal),
            address(0),
            0,
            address(0)
        );
        _expectEmit0();
        emit ZoraAuctionCreated(
            auctionId,
            proposalData.token,
            proposalData.tokenId,
            proposalData.listPrice,
            proposalData.duration,
            uint40(block.timestamp + proposalData.timeout)
        );
        assertTrue(proposal.executeListOnZora(executeParams).length > 0);
        assertEq(proposalData.token.ownerOf(proposalData.tokenId), address(ZORA));
    }

    function testForked_canBidOnListing() external onlyForked {
        (
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams,
            ListOnZoraProposal.ZoraProposalData memory proposalData
        ) = _createExecutionParams();
        uint256 auctionId = _getNextZoraAuctionId();
        proposal.executeListOnZora(executeParams);
        _bidOnListing(auctionId, proposalData.listPrice);
    }

    function testForked_canCancelExpiredListing() external onlyForked {
        (
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams,
            ListOnZoraProposal.ZoraProposalData memory proposalData
        ) = _createExecutionParams();
        uint256 auctionId = _getNextZoraAuctionId();
        executeParams.progressData = proposal.executeListOnZora(executeParams);
        skip(proposalData.timeout);
        _expectEmit3();
        emit AuctionCanceled(
            auctionId,
            proposalData.tokenId,
            address(proposalData.token),
            address(proposal)
        );
        _expectEmit0();
        emit ZoraAuctionExpired(auctionId, block.timestamp);
        assertTrue(proposal.executeListOnZora(executeParams).length == 0);
    }

    function testForked_cannotCancelUnexpiredListing() external onlyForked {
        (
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams,
            ListOnZoraProposal.ZoraProposalData memory proposalData
        ) = _createExecutionParams();
        uint256 auctionId = _getNextZoraAuctionId();
        executeParams.progressData = proposal.executeListOnZora(executeParams);
        skip(proposalData.timeout - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ListOnZoraProposal.ZoraListingNotExpired.selector,
                auctionId,
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
        uint256 auctionId = _getNextZoraAuctionId();
        executeParams.progressData = proposal.executeListOnZora(executeParams);
        _bidOnListing(auctionId, proposalData.listPrice);
        vm.expectRevert("Auction hasn't completed");
        proposal.executeListOnZora(executeParams);
    }

    function testForked_canSettleSuccessfulListing() external onlyForked {
        (
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams,
            ListOnZoraProposal.ZoraProposalData memory proposalData
        ) = _createExecutionParams();
        uint256 auctionId = _getNextZoraAuctionId();
        executeParams.progressData = proposal.executeListOnZora(executeParams);
        _bidOnListing(auctionId, proposalData.listPrice);
        skip(proposalData.duration);
        _expectEmit0();
        emit ZoraAuctionSold(auctionId);
        assertTrue(proposal.executeListOnZora(executeParams).length == 0);
        assertEq(address(proposal).balance, proposalData.listPrice);
    }

    function testForked_canSettleSuccessfulEndedListing() external onlyForked {
        (
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams,
            ListOnZoraProposal.ZoraProposalData memory proposalData
        ) = _createExecutionParams();
        uint256 auctionId = _getNextZoraAuctionId();
        executeParams.progressData = proposal.executeListOnZora(executeParams);
        _bidOnListing(auctionId, proposalData.listPrice);
        skip(proposalData.duration);
        ZORA.endAuction(auctionId);
        _expectEmit0();
        emit ZoraAuctionSold(auctionId);
        assertTrue(proposal.executeListOnZora(executeParams).length == 0);
        assertEq(address(proposal).balance, proposalData.listPrice);
    }

    function testForked_canSettleIfAuctionFails() external onlyForked {
        (
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams,
            ListOnZoraProposal.ZoraProposalData memory proposalData
        ) = _createExecutionParams();
        uint256 auctionId = _getNextZoraAuctionId();
        executeParams.progressData = proposal.executeListOnZora(executeParams);
        // Use a bidder that reverts when it receives the NFT, failing the entire
        // auction.
        _bidOnListing(address(new BadBidder()), auctionId, proposalData.listPrice);
        skip(proposalData.duration);
        _expectEmit0();
        emit ZoraAuctionFailed(auctionId);
        assertTrue(proposal.executeListOnZora(executeParams).length == 0);
        assertEq(address(proposal).balance, 0);
        assertEq(proposalData.token.ownerOf(proposalData.tokenId), address(proposal));
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
