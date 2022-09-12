// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "contracts/crowdfund/RecurringAuctionCrowdfund.sol";
import "contracts/globals/Globals.sol";
import "contracts/utils/Proxy.sol";
import "contracts/tokens/ERC721Receiver.sol";
import "./MockPartyFactory.sol";
import "./MockMarketWrapper.sol";

import "../TestUtils.sol";

contract RecurringAuctionCrowdfundTest is TestUtils, ERC721Receiver {
    event Won(uint256 bid, Party party);
    event Lost();
    event AuctionUpdated(uint256 newNftTokenId, uint256 newAuctionId, uint96 newMaximumBid);

    Globals globals;
    RecurringAuctionCrowdfund recurringAuctionCrowdfundImpl;
    RecurringAuctionCrowdfund crowdfund;
    MockPartyFactory partyFactory;
    MockMarketWrapper market;
    DummyERC721 nftContract;
    uint256 tokenId;
    uint256 auctionId;

    Crowdfund.FixedGovernanceOpts govOpts;

    constructor() {
        // Setup state
        globals = new Globals(address(this));
        partyFactory = new MockPartyFactory();
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));
        recurringAuctionCrowdfundImpl = new RecurringAuctionCrowdfund(globals);
        market = new MockMarketWrapper();
        nftContract = market.nftContract();
        (auctionId, tokenId) = market.createAuction(1 ether);

        // Set host
        govOpts.hosts = _toAddressArray(address(this));

        // Create crowdfund
        crowdfund = RecurringAuctionCrowdfund(payable(address(new Proxy(
            recurringAuctionCrowdfundImpl,
            abi.encodeCall(
                RecurringAuctionCrowdfund.initialize,
                RecurringAuctionCrowdfund.RecurringAuctionCrowdfundOptions({
                    name: "Crowfund",
                    symbol: "CF",
                    auctionId: auctionId,
                    market: market,
                    nftContract: nftContract,
                    nftTokenId: tokenId,
                    duration: 1 days,
                    maximumBid: type(uint96).max,
                    splitRecipient: payable(address(0)),
                    splitBps: 0,
                    initialContributor: address(this),
                    initialDelegate: address(this),
                    gateKeeper: IGateKeeper(address(0)),
                    gateKeeperId: 0,
                    governanceOpts: govOpts
                })
            )
        ))));

        // Contribute enough ETH to play with
        vm.deal(address(this), 100 ether);
        crowdfund.contribute{ value: 100 ether }(address(this), "");
    }

    function test_moveOnToNextAuctionAfterLoss() public {
        // Bid on the auction
        crowdfund.bid();

        // Get outbid
        _outbid();

        // End auction (we lost)
        market.endAuction(auctionId);

        // Create next auction.
        (auctionId, tokenId) = market.createAuction(1 ether);

        // Move on to next auction
        _expectEmit0();
        emit AuctionUpdated(tokenId, auctionId, type(uint96).max);
        crowdfund.finalize(govOpts, tokenId, auctionId, type(uint96).max);
        assertEq(crowdfund.auctionId(), auctionId);
        assertEq(crowdfund.nftTokenId(), tokenId);
        assertEq(crowdfund.lastBid(), 0);
    }

    function test_moveOnToNextAuctionAfterLoss_multipleTimes() public {
        for (uint256 i; i < 5; i++) test_moveOnToNextAuctionAfterLoss();
    }

    function test_moveOnToNextAuctionAfterLoss_thenWin() public {
        test_moveOnToNextAuctionAfterLoss();

        // Bid on the new auction
        crowdfund.bid();

        // End new auction
        market.endAuction(auctionId);

        // Finalize and win new auction
        _expectEmit0();
        emit Won(crowdfund.lastBid(), Party(payable(address(partyFactory.mockParty()))));
        Party party = crowdfund.finalize(govOpts, tokenId, auctionId, type(uint96).max);
        assertEq(address(nftContract.ownerOf(tokenId)), address(party));
        assertEq(address(crowdfund.party()), address(partyFactory.mockParty()));
    }

    function test_moveOnToNextAuctionAfterLoss_onlyHost() public {
        vm.expectRevert(RecurringAuctionCrowdfund.OnlyPartyHostError.selector);
        vm.prank(_randomAddress());
        crowdfund.finalize(govOpts, tokenId, auctionId, type(uint96).max);
    }

    // Calls the public `finalize()` that can be called by anyone, but expects
    // the auction to have been won otherwise reverts to be called by a host.
    function test_finalizeWinOnly() external {
        // Bid on the new auction
        crowdfund.bid();

        // End new auction
        market.endAuction(auctionId);

        // Finalize and win new auction
        _expectEmit0();
        emit Won(crowdfund.lastBid(), Party(payable(address(partyFactory.mockParty()))));
        Party party = crowdfund.finalize(govOpts);
        assertEq(address(nftContract.ownerOf(tokenId)), address(party));
        assertEq(address(crowdfund.party()), address(partyFactory.mockParty()));
    }

    function test_finalizeWinOnly_revertsIfAuctionLost() external {
        // Bid on the auction
        crowdfund.bid();

        // Get outbid
        _outbid();

        // End auction (we lost)
        market.endAuction(auctionId);

        vm.expectRevert(abi.encodeWithSelector(
            RecurringAuctionCrowdfund.AuctionLostError.selector,
            auctionId
        ));
        vm.prank(_randomAddress());
        crowdfund.finalize(govOpts);
    }

    function test_endCrowdfund() public {
        _expectEmit0();
        emit Lost();
        crowdfund.end(govOpts);

        uint256 balanceBefore = address(this).balance;
        crowdfund.burn(payable(address(this)));
        assertEq(address(this).balance, balanceBefore + 100 ether);
    }

    function test_endCrowdfund_expired() public {
        skip(1 days);

        _expectEmit0();
        emit Lost();
        vm.prank(_randomAddress());
        crowdfund.end(govOpts);
    }

    function test_endCrowdfund_onlyHostIfNotExpired() public {
        vm.expectRevert(RecurringAuctionCrowdfund.OnlyPartyHostError.selector);
        vm.prank(_randomAddress());
        crowdfund.end(govOpts);
    }

    function _outbid() internal {
        // Outbid the crowdfund.
        market.bid{ value: crowdfund.lastBid() + 1 }(auctionId, payable(address(this)));
    }

    receive() external payable {}
}