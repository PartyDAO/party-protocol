// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";
import { Clones } from "openzeppelin/contracts/proxy/Clones.sol";

import "../../contracts/crowdfund/AuctionCrowdfund.sol";
import "../../contracts/crowdfund/Crowdfund.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/vendor/markets/IFoundationMarket.sol";
import "../../contracts/renderers/RendererStorage.sol";

import "./MockPartyFactory.sol";
import "./MockParty.sol";
import "../DummyERC721.sol";

import "../TestUtils.sol";

contract FoundationCrowdfundForkedTest is TestUtils {
    using Clones for address;

    event Won(uint256 bid, Party party);
    event Lost();

    // Initialize party contracts
    Globals globals = new Globals(address(this));
    MockPartyFactory partyFactory = new MockPartyFactory();
    MockParty party = partyFactory.mockParty();
    AuctionCrowdfund pbImpl = new AuctionCrowdfund(globals);
    AuctionCrowdfund cf;

    Crowdfund.FixedGovernanceOpts govOpts;
    ProposalStorage.ProposalEngineOpts proposalEngineOpts;

    // Initialize Foundation contracts
    IFoundationMarket foundation = IFoundationMarket(0xcDA72070E455bb31C7690a170224Ce43623d0B6f);
    IMarketWrapper foundationMarket = IMarketWrapper(0x96e5b0519983f2f984324b926e6d28C3A4Eb92A1);
    FNDMiddleware foundationHelper = FNDMiddleware(0x22B111b81287138038b1b8DA0362B8C2f7A222fC);
    DummyERC721 nftContract = new DummyERC721();
    uint256 tokenId = nftContract.mint(address(this));
    uint256 auctionId;

    constructor() onlyForked {
        govOpts.partyImpl = Party(payable(address(party)));
        govOpts.partyFactory = partyFactory;

        // Initialize PartyFactory for creating parties after a successful crowdfund.
        globals.setAddress(
            LibGlobals.GLOBAL_RENDERER_STORAGE,
            address(new RendererStorage(address(this)))
        );

        // Create a reserve auction on Foundation to bid on
        nftContract.approve(address(foundation), tokenId);
        foundation.createReserveAuction(address(nftContract), tokenId, 1 ether);
        (, , , , , auctionId, , , , ) = foundationHelper.getNFTDetails(
            address(nftContract),
            tokenId
        );

        // Create a AuctionCrowdfund crowdfund
        cf = AuctionCrowdfund(payable(address(pbImpl).clone()));
        cf.initialize(
            AuctionCrowdfundBase.AuctionCrowdfundOptions({
                name: "Party",
                symbol: "PRTY",
                customizationPresetId: 0,
                auctionId: auctionId,
                market: foundationMarket,
                nftContract: nftContract,
                nftTokenId: tokenId,
                duration: 1 days,
                maximumBid: type(uint96).max,
                splitRecipient: payable(address(0)),
                splitBps: 0,
                initialContributor: address(this),
                initialDelegate: address(0),
                minContribution: 0,
                maxContribution: type(uint96).max,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: 0,
                onlyHostCanBid: false,
                governanceOpts: govOpts,
                proposalEngineOpts: proposalEngineOpts
            })
        );

        // Contribute ETH used to bid.
        vm.deal(address(this), 1000 ether);
        cf.contribute{ value: 1000 ether }(address(this), "");
    }

    // Test creating a crowdfund party around a Foundation auction + winning the auction
    function testForked_WinningFoundationAuction() external onlyForked {
        // Bid on current Foundation auction.
        cf.bid(govOpts, proposalEngineOpts, 0);

        // Check that we are highest bidder.
        uint256 lastBid = cf.lastBid();
        (, , address highestBidder, uint256 expiry, uint256 highestBid, , , , , ) = foundationHelper
            .getNFTDetails(address(nftContract), tokenId);
        assertEq(lastBid, highestBid);
        assertEq(address(cf), highestBidder);

        // Wait for the auction to end and check that we won.
        vm.warp(expiry + 1);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Won(lastBid, Party(payable(address(party))));
        cf.finalize(govOpts, proposalEngineOpts);
        assertEq(nftContract.ownerOf(tokenId), address(party));
        assertEq(address(cf.party()), address(party));
        assertTrue(foundationMarket.isFinalized(tokenId));
    }

    function testForked_WinningFoundationAuction_finalizedBefore() external onlyForked {
        // Bid on current Foundation auction.
        cf.bid(govOpts, proposalEngineOpts, 0);

        // Check that we are highest bidder.
        uint256 lastBid = cf.lastBid();
        (, , address highestBidder, uint256 expiry, uint256 highestBid, , , , , ) = foundationHelper
            .getNFTDetails(address(nftContract), tokenId);
        assertEq(lastBid, highestBid);
        assertEq(address(cf), highestBidder);

        // Wait for the auction to end and check that we won.
        vm.warp(expiry + 1);

        // Finalize the auction before `finalize()` is called by the crowdfund.
        foundationMarket.finalize(auctionId);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Won(lastBid, Party(payable(address(party))));
        cf.finalize(govOpts, proposalEngineOpts);
        assertEq(nftContract.ownerOf(tokenId), address(party));
        assertEq(address(cf.party()), address(party));
        assertTrue(foundationMarket.isFinalized(tokenId));
    }

    // Test creating a crowdfund party around a Foundation auction + losing the auction
    function testForked_LosingFoundationAuction() external onlyForked {
        // Bid on current Foundation auction.
        cf.bid(govOpts, proposalEngineOpts, 0);

        // We outbid our own party (sneaky!)
        vm.deal(address(this), 1001 ether);
        foundation.placeBid{ value: 1001 ether }(auctionId);

        // Wait for the auction to end and check that we lost.
        (, , , uint256 expiry, , , , , , ) = foundationHelper.getNFTDetails(
            address(nftContract),
            tokenId
        );
        vm.warp(expiry + 1);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Lost();
        cf.finalize(govOpts, proposalEngineOpts);
        assertEq(address(cf.party()), address(0));
        assertTrue(foundationMarket.isFinalized(tokenId));
    }

    function testForked_LosingFoundationAuction_finalizedBefore() external onlyForked {
        // Bid on current Foundation auction.
        cf.bid(govOpts, proposalEngineOpts, 0);

        // We outbid our own party (sneaky!)
        vm.deal(address(this), 1001 ether);
        foundation.placeBid{ value: 1001 ether }(auctionId);

        // Wait for the auction to end and check that we lost.
        (, , , uint256 expiry, , , , , , ) = foundationHelper.getNFTDetails(
            address(nftContract),
            tokenId
        );
        vm.warp(expiry + 1);

        // Finalize the auction before `finalize()` is called by the crowdfund.
        foundationMarket.finalize(auctionId);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Lost();
        cf.finalize(govOpts, proposalEngineOpts);
        assertEq(address(cf.party()), address(0));
        assertTrue(foundationMarket.isFinalized(tokenId));
    }
}

interface FNDMiddleware {
    function getNFTDetails(
        address nftContract,
        uint256 tokenId
    )
        external
        view
        returns (
            address owner,
            bool isInEscrow,
            address auctionBidder,
            uint256 auctionEndTime,
            uint256 auctionPrice,
            uint256 auctionId,
            uint256 buyPrice,
            uint256 offerAmount,
            address offerBuyer,
            uint256 offerExpiration
        );
}
