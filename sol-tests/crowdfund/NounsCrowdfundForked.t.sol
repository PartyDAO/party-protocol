// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/AuctionCrowdfund.sol";
import "../../contracts/crowdfund/Crowdfund.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/utils/Proxy.sol";
import "../../contracts/vendor/markets/INounsAuctionHouse.sol";

import "./MockPartyFactory.sol";
import "./MockParty.sol";

import "../TestUtils.sol";

contract NounsCrowdfundForkedTest is TestUtils {
    event Won(uint256 bid, Party party);
    event Lost();

    // Initialize party contracts
    Globals globals = new Globals(address(this));
    MockPartyFactory partyFactory = new MockPartyFactory();
    MockParty party = partyFactory.mockParty();
    AuctionCrowdfund pbImpl = new AuctionCrowdfund(globals);
    AuctionCrowdfund cf;

    Crowdfund.FixedGovernanceOpts defaultGovOpts;

    // Initialize nouns contracts
    INounsAuctionHouse nounsAuctionHouse =
        INounsAuctionHouse(0x830BD73E4184ceF73443C15111a1DF14e495C706);
    IMarketWrapper nounsMarket = IMarketWrapper(0x9319DAd8736D752C5c72DB229f8e1b280DC80ab1);
    IERC721 nounsToken;
    uint256 tokenId;

    constructor() onlyForked {
        // Initialize PartyFactory for creating parties after a successful crowdfund.
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));

        nounsToken = nounsAuctionHouse.nouns();
        (tokenId, , , , , ) = nounsAuctionHouse.auction();

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
                                market: nounsMarket,
                                nftContract: nounsToken,
                                nftTokenId: tokenId,
                                duration: type(uint32).max,
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

    // Test creating a crowdfund party around a Noun + winning the auction
    function testForked_WinningNounAuction() external onlyForked {
        // Bid on current Noun auction.
        cf.bid(defaultGovOpts, 0);

        // Check that we are highest bidder.
        uint256 lastBid = cf.lastBid();
        (, uint256 highestBid, , , address payable highestBidder, ) = nounsAuctionHouse.auction();
        assertEq(lastBid, highestBid);
        assertEq(address(cf), highestBidder);

        // Wait for the auction to end and check that we won.
        skip(1 days);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Won(lastBid, Party(payable(address(party))));
        cf.finalize(defaultGovOpts);
        assertEq(nounsToken.ownerOf(tokenId), address(party));
        assertEq(address(cf.party()), address(party));
        assertTrue(nounsMarket.isFinalized(tokenId));
    }

    function testForked_WinningNounsAuction_finalizedBefore() external onlyForked {
        // Bid on current Noun auction.
        cf.bid(defaultGovOpts, 0);

        // Check that we are highest bidder.
        uint256 lastBid = cf.lastBid();
        (, uint256 highestBid, , , address payable highestBidder, ) = nounsAuctionHouse.auction();
        assertEq(lastBid, highestBid);
        assertEq(address(cf), highestBidder);

        // Wait for the auction to end and check that we won.
        skip(1 days);

        // Finalize the auction before `finalize()` is called by the crowdfund.
        nounsMarket.finalize(tokenId);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Won(lastBid, Party(payable(address(party))));
        cf.finalize(defaultGovOpts);
        assertEq(nounsToken.ownerOf(tokenId), address(party));
        assertEq(address(cf.party()), address(party));
        assertTrue(nounsMarket.isFinalized(tokenId));
    }

    // Test creating a crowdfund party around a Noun + losing the auction
    function testForked_LosingNounAuction() external onlyForked {
        // Bid on current Noun auction.
        cf.bid(defaultGovOpts, 0);

        // We outbid our own party (sneaky!)
        vm.deal(address(this), 1001 ether);
        nounsAuctionHouse.createBid{ value: 1001 ether }(tokenId);

        // Wait for the auction to end and check that we lost.
        skip(1 days);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Lost();
        cf.finalize(defaultGovOpts);
        assertEq(address(cf.party()), address(0));
        assertTrue(nounsMarket.isFinalized(tokenId));
    }

    function testForked_LosingNounAuction_finalizeBefore() external onlyForked {
        // Bid on current Noun auction.
        cf.bid(defaultGovOpts, 0);

        // We outbid our own party (sneaky!)
        vm.deal(address(this), 1001 ether);
        nounsAuctionHouse.createBid{ value: 1001 ether }(tokenId);

        // Wait for the auction to end and check that we lost.
        skip(1 days);

        // Finalize the auction before `finalize()` is called by the crowdfund.
        nounsMarket.finalize(tokenId);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Lost();
        cf.finalize(defaultGovOpts);
        assertEq(address(cf.party()), address(0));
        assertTrue(nounsMarket.isFinalized(tokenId));
    }
}
