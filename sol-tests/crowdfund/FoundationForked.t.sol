// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/PartyBid.sol";
import "../../contracts/crowdfund/PartyCrowdfund.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/utils/Proxy.sol";
import "../../contracts/market-wrapper/FoundationMarketWrapper.sol";

import "./MockPartyFactory.sol";
import "./MockParty.sol";
import "../DummyERC721.sol";

import "../TestUtils.sol";

interface FNDMiddleware {
    function getNFTDetails(address nftContract, uint256 tokenId)
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

contract FoundationForkedTest is TestUtils {
    event Won(uint256 bid, Party party);
    event Lost();

    // Initialize party contracts
    Globals globals = new Globals(address(this));
    MockPartyFactory partyFactory = new MockPartyFactory();
    MockParty party = partyFactory.mockParty();
    PartyBid pbImpl = new PartyBid(globals);
    PartyBid pb;

    PartyCrowdfund.FixedGovernanceOpts defaultGovOpts;

    // Initialize Foundation contracts
    IFoundationMarket foundation = IFoundationMarket(
        0xcDA72070E455bb31C7690a170224Ce43623d0B6f
    );
    FoundationMarketWrapper foundationMarket = new FoundationMarketWrapper(
        address(foundation)
    );
    FNDMiddleware foundationHelper = FNDMiddleware(0x22B111b81287138038b1b8DA0362B8C2f7A222fC);
    DummyERC721 nftContract = new DummyERC721();
    uint256 tokenId = nftContract.mint(address(this));
    uint256 auctionId;

    constructor() onlyForked {
        // Initialize PartyFactory for creating parties after a successful crowdfund.
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));

        // Create a reserve auction on Foundation to bid on
        nftContract.approve(address(foundation), tokenId);
        foundation.createReserveAuction(address(nftContract), tokenId, 1 ether);
        (, , , , , auctionId, , , ,) =
            foundationHelper.getNFTDetails(address(nftContract), tokenId);

        // Create a PartyBid crowdfund
        pb = PartyBid(payable(address(new Proxy(
            pbImpl,
            abi.encodeCall(
                PartyBid.initialize,
                PartyBid.PartyBidOptions({
                    name: "Party",
                    symbol: "PRTY",
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
                    gateKeeper: IGateKeeper(address(0)),
                    gateKeeperId: 0,
                    governanceOpts: defaultGovOpts
                })
            )
        ))));

        // Contribute ETH used to bid.
        vm.deal(address(this), 1000 ether);
        pb.contribute{ value: 1000 ether }(address(this), "");
    }

    // Test creating a crowdfund party around a Foundation auction + winning the auction
    function testWinningFoundationAuction() external onlyForked {
        // Bid on current Foundation auction.
        pb.bid();

        // Check that we are highest bidder.
        uint256 lastBid = pb.lastBid();
        (, , address highestBidder, uint256 endTime, uint256 highestBid, , , , ,) =
            foundationHelper.getNFTDetails(address(nftContract), tokenId);
        assertEq(lastBid, highestBid);
        assertEq(address(pb), highestBidder);

        // Wait for the auction to end and check that we won.
        vm.warp(endTime + 1);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Won(lastBid, Party(payable(address(party))));
        pb.finalize(defaultGovOpts);
        assertEq(nftContract.ownerOf(tokenId), address(party));
        assertEq(address(pb.party()), address(party));
        assertTrue(foundationMarket.isFinalized(tokenId));
    }

    // Test creating a crowdfund party around a Foundation auction + losing the auction
    function testLosingNounAuction() external onlyForked {
        // Bid on current Foundation auction.
        pb.bid();

        // We outbid our own party (sneaky!)
        vm.deal(address(this), 1001 ether);
        foundation.placeBid{ value: 1001 ether }(auctionId);

        // Wait for the auction to end and check that we lost.
        (, , , uint256 endTime, , , , , ,) =
            foundationHelper.getNFTDetails(address(nftContract), tokenId);
        vm.warp(endTime + 1);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Lost();
        pb.finalize(defaultGovOpts);
        assertEq(address(pb.party()), address(0));
        assertTrue(foundationMarket.isFinalized(tokenId));
    }
}