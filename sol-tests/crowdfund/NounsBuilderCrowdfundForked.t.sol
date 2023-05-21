// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/AuctionCrowdfund.sol";
import "../../contracts/crowdfund/Crowdfund.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/utils/Proxy.sol";
import "../../contracts/vendor/markets/INounsBuilderAuctionHouse.sol";

import "./MockPartyFactory.sol";
import "./MockParty.sol";
import "../DummyERC721.sol";

import "../TestUtils.sol";

contract NounsBuilderCrowdfundForkedTest is TestUtils, ERC721Receiver {
    event Won(uint256 bid, Party party);
    event Lost();

    // Initialize party contracts
    Globals globals = new Globals(address(this));
    MockPartyFactory partyFactory = new MockPartyFactory();
    MockParty party = partyFactory.mockParty();
    AuctionCrowdfund pbImpl = new AuctionCrowdfund(globals);
    AuctionCrowdfund cf;

    Crowdfund.FixedGovernanceOpts defaultGovOpts;

    // Initialize Nouns Builder contracts
    INounsBuilderAuctionHouse nounsBuilder = INounsBuilderAuctionHouse(0xE468cE99444174Bd3bBBEd09209577d25D1ad673);
    IMarketWrapper nounsBuilderMarket = IMarketWrapper(0x11c07cE1315a3b92C9755F90cDF40B04b88c5731);
    IERC721 token;
    uint256 tokenId;

    constructor() onlyForked {
        // Initialize PartyFactory for creating parties after a successful crowdfund.
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));

        token = nounsBuilder.token();
        (tokenId, , , , , ) = nounsBuilder.auction();

        // Create a AuctionCrowdfund crowdfund
        cf = AuctionCrowdfund(
            payable(
                address(
                    new Proxy(
                        pbImpl,
                        abi.encodeCall(
                            AuctionCrowdfund.initialize,
                            AuctionCrowdfundBase.AuctionCrowdfundOptions({
                                name: "Party",
                                symbol: "PRTY",
                                customizationPresetId: 0,
                                auctionId: tokenId,
                                market: nounsBuilderMarket,
                                nftContract: token,
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
                                governanceOpts: defaultGovOpts
                            })
                        )
                    )
                )
            )
        );

        // Contribute ETH used to bid.
        vm.deal(address(this), 1000 ether);
        cf.contribute{ value: 1000 ether }(address(this), "");
    }

    // Test creating a crowdfund party around a Nouns Builder auction + winning the auction
    function testForked_WinningNounsBuilderAuction() external onlyForked {
        // Bid on current Nouns Builder auction.
        cf.bid(defaultGovOpts, 0);

        // Check that we are highest bidder.
        uint256 lastBid = cf.lastBid();
        (, uint256 highestBid, address highestBidder, , , ) = nounsBuilder.auction();
        assertEq(lastBid, highestBid);
        assertEq(address(cf), highestBidder);

        // Wait for the auction to end and check that we won.
        skip(1 days);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Won(lastBid, Party(payable(address(party))));
        cf.finalize(defaultGovOpts);
        assertEq(token.ownerOf(tokenId), address(party));
        assertEq(address(cf.party()), address(party));
        assertTrue(nounsBuilderMarket.isFinalized(tokenId));
    }

    function testForked_WinningNounsBuilderAuction_finalizeBefore() external onlyForked {
        // Bid on current Nouns Builder auction.
        cf.bid(defaultGovOpts, 0);

        // Check that we are highest bidder.
        uint256 lastBid = cf.lastBid();
        (, uint256 highestBid, address highestBidder, , , , ) = nounsBuilder.auction();
        assertEq(lastBid, highestBid);
        assertEq(address(cf), highestBidder);

        // Wait for the auction to end and check that we won.
        skip(1 days);

        // Finalize the auction before `finalize()` is called by the crowdfund.
        nounsBuilder.finalize(tokenId);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Won(lastBid, Party(payable(address(party))));
        cf.finalize(defaultGovOpts);
        assertEq(token.ownerOf(tokenId), address(party));
        assertEq(address(cf.party()), address(party));
        assertTrue(nounsBuilderMarket.isFinalized(tokenId));
    }

    // Test creating a crowdfund party around a Nouns Builder auction + losing the auction
    function testForked_LosingNounsBuilderAuction() external onlyForked {
        // Bid on current Nouns Builder auction.
        cf.bid(defaultGovOpts, 0);

        // We outbid our own party (sneaky!)
        vm.deal(address(this), 1001 ether);
        nounsBuilder.createBid{ value: 1001 ether }(tokenId);

        // Wait for the auction to end and check that we lost.
        skip(1 days);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Lost();
        cf.finalize(defaultGovOpts);
        assertEq(address(cf.party()), address(0));
        assertTrue(nounsBuilderMarket.isFinalized(tokenId));
    }

    function testForked_LosingNounsBuilderAuction_finalizeBefore() external onlyForked {
        // Bid on current Nouns Builder auction.
        cf.bid(defaultGovOpts, 0);

        // We outbid our own party (sneaky!)
        vm.deal(address(this), 1001 ether);
        nounsBuilder.createBid{ value: 1001 ether }(tokenId);

        // Wait for the auction to end and check that we lost.
        skip(1 days);

        // Finalize the auction before `finalize()` is called by the crowdfund.
        nounsBuilderMarket.finalize(tokenId);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Lost();
        cf.finalize(defaultGovOpts);
        assertEq(address(cf.party()), address(0));
        assertTrue(nounsBuilderMarket.isFinalized(tokenId));
    }
}
