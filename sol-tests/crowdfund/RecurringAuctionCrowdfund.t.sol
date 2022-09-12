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

    bool onlyRunIfForked;

    Globals globals;
    RecurringAuctionCrowdfund recurringAuctionCrowdfundImpl;
    RecurringAuctionCrowdfund crowdfund;
    MockPartyFactory partyFactory;
    IMarketWrapper market;
    IERC721 nftContract;
    uint256 tokenId;
    uint256 auctionId;

    Crowdfund.FixedGovernanceOpts govOpts;

    // This is for other test inheriting from this test; this can be ignored for
    // this file as it will always be false.
    modifier onlyForkedIfSet() {
        if (onlyRunIfForked && block.number < 1e6) {
            return;
        }
        _;
    }

    function setUp() public virtual onlyForkedIfSet() {
        // Setup state
        globals = new Globals(address(this));
        partyFactory = new MockPartyFactory();
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));
        recurringAuctionCrowdfundImpl = new RecurringAuctionCrowdfund(globals);
        market = IMarketWrapper(new MockMarketWrapper());
        nftContract = IERC721(address(MockMarketWrapper(address(market)).nftContract()));
        _createNextAuction();

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

    function test_moveOnToNextAuctionAfterLoss() public onlyForkedIfSet {
        // Bid on the auction
        crowdfund.bid();

        _outbid();

        _endAuction();

        _createNextAuction();

        // Move on to next auction
        _expectEmit0();
        emit AuctionUpdated(tokenId, auctionId, type(uint96).max);
        crowdfund.finalize(govOpts, tokenId, auctionId, type(uint96).max);
        assertEq(crowdfund.auctionId(), auctionId);
        assertEq(crowdfund.nftTokenId(), tokenId);
        assertEq(crowdfund.lastBid(), 0);
    }

    function test_moveOnToNextAuctionAfterLoss_multipleTimes() public onlyForkedIfSet {
        for (uint256 i; i < 5; i++) test_moveOnToNextAuctionAfterLoss();
    }

    function test_moveOnToNextAuctionAfterLoss_thenWin() public onlyForkedIfSet {
        test_moveOnToNextAuctionAfterLoss();

        // Bid on the new auction
        crowdfund.bid();

        _endAuction();

        // Finalize and win new auction
        _expectEmit0();
        emit Won(crowdfund.lastBid(), Party(payable(address(partyFactory.mockParty()))));
        Party party = crowdfund.finalize(govOpts, tokenId, auctionId, type(uint96).max);
        assertEq(address(nftContract.ownerOf(tokenId)), address(party));
        assertEq(address(crowdfund.party()), address(partyFactory.mockParty()));
    }

    function test_moveOnToNextAuctionAfterLoss_onlyHost() public onlyForkedIfSet {
        vm.expectRevert(RecurringAuctionCrowdfund.OnlyPartyHostError.selector);
        vm.prank(_randomAddress());
        crowdfund.finalize(govOpts, tokenId, auctionId, type(uint96).max);
    }

    // Calls the public `finalize()` that can be called by anyone, but expects
    // the auction to have been won otherwise reverts to be called by a host.
    function test_finalizeWinOnly() public onlyForkedIfSet {
        // Bid on the auction
        crowdfund.bid();

        _endAuction();

        // Finalize and win auction
        _expectEmit0();
        emit Won(crowdfund.lastBid(), Party(payable(address(partyFactory.mockParty()))));
        Party party = crowdfund.finalize(govOpts);
        assertEq(address(nftContract.ownerOf(tokenId)), address(party));
        assertEq(address(crowdfund.party()), address(partyFactory.mockParty()));
    }

    function test_finalizeWinOnly_revertsIfAuctionLost() public onlyForkedIfSet {
        // Bid on the auction
        crowdfund.bid();

        // Get outbid
        _outbid();

        _endAuction();

        vm.expectRevert(abi.encodeWithSelector(
            RecurringAuctionCrowdfund.AuctionLostError.selector,
            auctionId
        ));
        vm.prank(_randomAddress());
        crowdfund.finalize(govOpts);
    }

    function test_finalize_declareLostIfExpiredWithoutNFT() public onlyForkedIfSet {
        _endAuction();

        _skipToExpiry();

        _expectEmit0();
        emit Lost();
        vm.prank(_randomAddress());
        crowdfund.finalize(govOpts);
        assertEq(address(crowdfund.party()), address(0));
    }

    function test_finalize_declareWinIfExpiredWithNFT() public onlyForkedIfSet {
        // Bid on the auction
        crowdfund.bid();

        _endAuction();

        _skipToExpiry();

        _expectEmit0();
        emit Won(crowdfund.lastBid(), Party(payable(address(partyFactory.mockParty()))));
        vm.prank(_randomAddress());
        crowdfund.finalize(govOpts);
        assertEq(address(crowdfund.party()), address(partyFactory.mockParty()));
    }

    function test_endCrowdfund() public onlyForkedIfSet {
        _expectEmit0();
        emit Lost();
        crowdfund.end(govOpts);

        uint256 balanceBefore = address(this).balance;
        crowdfund.burn(payable(address(this)));
        assertEq(address(this).balance, balanceBefore + crowdfund.totalContributions());
    }

    function test_endCrowdfund_onlyHost() public onlyForkedIfSet {
        vm.expectRevert(RecurringAuctionCrowdfund.OnlyPartyHostError.selector);
        vm.prank(_randomAddress());
        crowdfund.end(govOpts);
    }

    function _createNextAuction() internal virtual {
        (auctionId, tokenId) = MockMarketWrapper(address(market)).createAuction(1 ether);
    }

    function _endAuction() internal virtual {
        MockMarketWrapper(address(market)).endAuction(auctionId);
    }

    function _skipToExpiry() internal virtual {
        skip(1 days);
        assertEq(uint8(crowdfund.getCrowdfundLifecycle()), uint8(Crowdfund.CrowdfundLifecycle.Expired));
    }

    function _outbid() internal virtual {
        // Outbid the crowdfund.
        vm.deal(address(this), 101 ether);
        MockMarketWrapper(address(market)).bid{ value: 101 ether }(auctionId, payable(address(this)));
    }

    receive() external payable {}
}