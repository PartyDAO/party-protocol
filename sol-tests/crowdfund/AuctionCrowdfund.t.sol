// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/AuctionCrowdfund.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/utils/Proxy.sol";

import "../DummyERC721.sol";
import "../TestUtils.sol";

import "./MockPartyFactory.sol";
import "./MockParty.sol";
import "./MockMarketWrapper.sol";

contract AuctionCrowdfundTest is Test, TestUtils {
    event MockPartyFactoryCreateParty(
        address caller,
        address authority,
        Party.PartyOptions opts,
        IERC721[] preciousTokens,
        uint256[] preciousTokenIds
    );

    event MockMint(
        address caller,
        address owner,
        uint256 amount,
        address delegate
    );

    event MockMarketWrapperBid(
        address bidder,
        uint256 auctionId,
        uint256 bidAmount
    );

    event MockMarketWrapperFinalize(
        address caller,
        address winner,
        uint256 topBid
    );

    event Burned(address contributor, uint256 ethUsed, uint256 ethOwed, uint256 votingPower);
    event Contributed(address contributor, uint256 amount, address delegate, uint256 previousTotalContributions);
    event Won(uint256 bid, Party party);
    event Lost();

    string defaultName = 'AuctionCrowdfund';
    string defaultSymbol = 'PBID';
    uint40 defaultDuration = 60 * 60;
    uint96 defaultMaxBid = 10e18;
    address payable defaultSplitRecipient = payable(0);
    uint16 defaultSplitBps = 0.1e4;
    address defaultInitialDelegate;
    IGateKeeper defaultGateKeeper;
    bytes12 defaultGateKeeperId;
    Crowdfund.FixedGovernanceOpts defaultGovernanceOpts;

    Globals globals = new Globals(address(this));
    MockPartyFactory partyFactory = new MockPartyFactory();
    MockMarketWrapper market = new MockMarketWrapper();
    DummyERC721 tokenToBuy;
    AuctionCrowdfund auctionCrowdfundImpl;
    MockParty party;

    constructor() {
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));
        tokenToBuy = market.nftContract();
        party = partyFactory.mockParty();
        auctionCrowdfundImpl = new AuctionCrowdfund(globals);
    }

    function _createCrowdfund(
        uint256 auctionId,
        uint256 tokenId,
        uint96 initialContribution
    )
        private
        returns (AuctionCrowdfund pb)
    {
        pb = AuctionCrowdfund(payable(address(new Proxy{ value: initialContribution }(
            auctionCrowdfundImpl,
            abi.encodeCall(
                AuctionCrowdfund.initialize,
                AuctionCrowdfund.AuctionCrowdfundOptions({
                    name: defaultName,
                    symbol: defaultSymbol,
                    auctionId: auctionId,
                    market: market,
                    nftContract: tokenToBuy,
                    nftTokenId: tokenId,
                    duration: defaultDuration,
                    maximumBid: defaultMaxBid,
                    splitRecipient: defaultSplitRecipient,
                    splitBps: defaultSplitBps,
                    initialContributor: address(this),
                    initialDelegate: defaultInitialDelegate,
                    gateKeeper: defaultGateKeeper,
                    gateKeeperId: defaultGateKeeperId,
                    governanceOpts: defaultGovernanceOpts
                })
            )
        ))));
    }

    function _createExpectedPartyOptions(uint256 finalPrice)
        private
        view
        returns (Party.PartyOptions memory opts)
    {
        return Party.PartyOptions({
            name: defaultName,
            symbol: defaultSymbol,
            governance: PartyGovernance.GovernanceOpts({
                hosts: defaultGovernanceOpts.hosts,
                voteDuration: defaultGovernanceOpts.voteDuration,
                executionDelay: defaultGovernanceOpts.executionDelay,
                passThresholdBps: defaultGovernanceOpts.passThresholdBps,
                totalVotingPower: uint96(finalPrice),
                feeBps: defaultGovernanceOpts.feeBps,
                feeRecipient: defaultGovernanceOpts.feeRecipient
            })
        });
    }

    function test_happyPath() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        _contribute(pb, contributor, delegate, 1e18);
        // Bid on the auction.
        _expectEmit0();
        emit MockMarketWrapperBid(address(pb), auctionId, 1337);
        pb.bid();
        // End the auction.
        _expectEmit0();
        emit MockMarketWrapperFinalize(address(pb), address(pb), 1337);
        market.endAuction(auctionId);
        // Finalize the crowdfund.
        _expectEmit0();
        emit MockPartyFactoryCreateParty(
            address(pb),
            address(pb),
            _createExpectedPartyOptions(1337),
            _toERC721Array(tokenToBuy),
            _toUint256Array(tokenId)
        );
        Party party_ = pb.finalize(defaultGovernanceOpts);
        assertEq(address(party_), address(party));
        // Burn contributor's NFT, mock minting governance tokens and returning
        // unused contribution.
        _expectEmit0();
        emit MockMint(
            address(pb),
            contributor,
            1337,
            delegate
        );
        _expectEmit0();
        emit Burned(contributor, 1337, 1e18 - 1337, 1337);
        pb.burn(contributor);
        assertEq(contributor.balance, 1e18 - 1337);
    }

    function test_cannotReinitialize() external {
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        vm.expectRevert(abi.encodeWithSelector(Implementation.OnlyConstructorError.selector));
        AuctionCrowdfund.AuctionCrowdfundOptions memory opts;
        pb.initialize(opts);
    }

    function test_canRefundIfCrowdfundLosesAndNoBidsMade() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(pb, contributor, 1e18);
        // Expire and finalize the crowdfund.
        skip(defaultDuration);
        Party party_ = pb.finalize(defaultGovernanceOpts);
        assertEq(address(party_), address(0));
        // Burn contributor's NFT, which should refund all contributed ETH.
        _expectEmit0();
        emit Burned(contributor, 0, 1e18, 0);
        pb.burn(contributor);
        assertEq(contributor.balance, 1e18);
    }

    function test_canRefundIfCrowdfundLosesWithBidsMade_notFinalized() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(pb, contributor, 1e18);
        // Bid on the auction.
        pb.bid();
        // Outbid externally so we're losing.
        _outbidExternally(auctionId);
        // End the auction.
        market.endAuction(auctionId);
        // Expire and finalize the crowdfund.
        skip(defaultDuration);
        Party party_ = pb.finalize(defaultGovernanceOpts);
        assertEq(address(party_), address(0));
        // Burn contributor's NFT, which should refund all contributed ETH.
        _expectEmit0();
        emit Burned(contributor, 0, 1e18, 0);
        pb.burn(contributor);
        assertEq(contributor.balance, 1e18);
    }

    function test_canRefundIfCrowdfundLosesWithBidsMade_finalized() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(pb, contributor, 1e18);
        // Bid on the auction.
        pb.bid();
        // Outbid externally so we're losing.
        _outbidExternally(auctionId);
        // End the auction and finalize it.
        market.endAuction(auctionId);
        market.finalize(auctionId);
        // Expire and finalize the crowdfund.
        skip(defaultDuration);
        Party party_ = pb.finalize(defaultGovernanceOpts);
        assertEq(address(party_), address(0));
        // Burn contributor's NFT, which should refund all contributed ETH.
        _expectEmit0();
        emit Burned(contributor, 0, 1e18, 0);
        pb.burn(contributor);
        assertEq(contributor.balance, 1e18);
    }

    function test_canWinEvenIfExpiredIfAlsoTopBidder() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(pb, contributor, 1e18);
        // Bid on the auction.
        pb.bid();
        // Expire and finalize the crowdfund.
        skip(defaultDuration);
        assertEq(uint8(pb.getCrowdfundLifecycle()), uint8(Crowdfund.CrowdfundLifecycle.Expired));
        // End the auction.
        market.endAuction(auctionId);
        // Finalize the crowdfund.
        Party party_ = pb.finalize(defaultGovernanceOpts);
        assertEq(address(party_), address(party));
        // Burn contributor's NFT, which should refund unused ETH and mint voting power.
        _expectEmit0();
        emit Burned(contributor, 1337, 1e18 - 1337, 1337);
        pb.burn(contributor);
        assertEq(contributor.balance, 1e18 - 1337);
    }

    function test_cannotBidAfterFinalize() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(pb, contributor, 1e18);
        // Bid on the auction.
        pb.bid();
        // End the auction.
        market.endAuction(auctionId);
        // Finalize the crowdfund.
        Party party_ = pb.finalize(defaultGovernanceOpts);
        assertEq(address(party_), address(party));
        // Try to bid with the crowdfund again.
        vm.expectRevert(abi.encodeWithSelector(
            Crowdfund.WrongLifecycleError.selector,
            Crowdfund.CrowdfundLifecycle.Won
        ));
        pb.bid();
    }

    function test_cannotFinalizeTwice() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(pb, contributor, 1e18);
        // Bid on the auction.
        pb.bid();
        // End the auction.
        market.endAuction(auctionId);
        // Finalize the crowdfund.
        Party party_ = pb.finalize(defaultGovernanceOpts);
        assertEq(address(party_), address(party));
        // Try to finalize the crowdfund again.
        vm.expectRevert(abi.encodeWithSelector(
            Crowdfund.WrongLifecycleError.selector,
            Crowdfund.CrowdfundLifecycle.Won
        ));
        pb.finalize(defaultGovernanceOpts);
    }

    function test_cannotFinalizeTooEarlyWithNoBids() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(pb, contributor, 1e18);
        // Finalize the crowdfund early.
        vm.expectRevert(abi.encodeWithSelector(
            AuctionCrowdfund.AuctionNotExpiredError.selector
        ));
        pb.finalize(defaultGovernanceOpts);
    }

    function test_canFinalizeIfExpiredBeforeAuctionEnds_noBids() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(pb, contributor, 1e18);
        skip(defaultDuration);
        _expectEmit0();
        emit Lost();
        // Finalize the crowdfund.
        pb.finalize(defaultGovernanceOpts);
    }

    function test_canFinalizeIfExpiredAfterAuctionEnds_noBids() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(pb, contributor, 1e18);
        skip(defaultDuration);
        market.endAuction(auctionId);
        _expectEmit0();
        emit Lost();
        // Finalize the crowdfund.
        pb.finalize(defaultGovernanceOpts);
    }

    function test_canFinalizeIfExpiredAndAuctionFinalized_noBids() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(pb, contributor, 1e18);
        skip(defaultDuration);
        market.endAuction(auctionId);
        market.finalize(auctionId);
        _expectEmit0();
        emit Lost();
        // Finalize the crowdfund.
        pb.finalize(defaultGovernanceOpts);
    }

    function test_cannotFinalizeIfExpiredBeforeAuctionEnds_withBid() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(pb, contributor, 1e18);
        // Place a bid.
        pb.bid();
        // Expire the CF.
        skip(defaultDuration);
        vm.expectRevert('AUCTION_NOT_ENDED');
        // Try to finalize the crowdfund. This will fail because even though the
        // CF is expired, the auction cannot be finalized.
        pb.finalize(defaultGovernanceOpts);
    }

    function test_canFinalizeIfExpiredAfterAuctionEnds_withBids() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(pb, contributor, 1e18);
        uint256 bid = market.getMinimumBid(auctionId);
        // Place a bid.
        pb.bid();
        // Expire the CF.
        skip(defaultDuration);
        // End the auction.
        market.endAuction(auctionId);
        _expectEmit0();
        emit Won(bid, Party(payable(address(party))));
        pb.finalize(defaultGovernanceOpts);
    }

    function test_cannotReenterFinalize() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(pb, contributor, 1e18);
        // Bid on the auction.
        pb.bid();
        // End the auction.
        market.endAuction(auctionId);
        // Set up a callback to reenter finalize().
        market.setCallback(address(pb), abi.encodeCall(pb.finalize, defaultGovernanceOpts), 0);
        // Finalize the crowdfund.
        vm.expectRevert(abi.encodeWithSelector(
            Crowdfund.WrongLifecycleError.selector,
            Crowdfund.CrowdfundLifecycle.Busy
        ));
        pb.finalize(defaultGovernanceOpts);
    }

    function test_cannotReenterBid() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(pb, contributor, 1e18);
        // Set up a callback to reenter bid().
        market.setCallback(address(pb), abi.encodeCall(pb.bid, ()), 0);
        // Bid on the auction.
        vm.expectRevert(abi.encodeWithSelector(
            Crowdfund.WrongLifecycleError.selector,
            Crowdfund.CrowdfundLifecycle.Busy
        ));
        pb.bid();
    }

    function test_cannotReenterContributeThroughBid() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(pb, contributor, 1e18);
        // Set up a callback to reenter bid().
        market.setCallback(address(pb), abi.encodeCall(pb.contribute, (contributor, "")), 1);
        // Bid on the auction.
        vm.expectRevert(abi.encodeWithSelector(
            Crowdfund.WrongLifecycleError.selector,
            Crowdfund.CrowdfundLifecycle.Busy
        ));
        pb.bid();
    }

    function test_cannotReenterContributeThroughFinalize() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(pb, contributor, 1e18);
        // Bid on the auction.
        pb.bid();
        // End the auction.
        market.endAuction(auctionId);
        // Set up a callback to reenter contribute().
        market.setCallback(address(pb), abi.encodeCall(pb.contribute, (contributor, "")), 1);
        // Finalize the crowdfund.
        vm.expectRevert(abi.encodeWithSelector(
            Crowdfund.WrongLifecycleError.selector,
            Crowdfund.CrowdfundLifecycle.Busy
        ));
        pb.finalize(defaultGovernanceOpts);
    }

    function test_creation_initialContribution() external {
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        uint256 initialContribution = _randomRange(1, 1 ether);
        address initialContributor = _randomAddress();
        address initialDelegate = _randomAddress();
        vm.deal(address(this), initialContribution);
        emit Contributed(initialContributor, initialContribution, initialDelegate, 0);
        AuctionCrowdfund(payable(address(new Proxy{ value: initialContribution }(
            auctionCrowdfundImpl,
            abi.encodeCall(
                AuctionCrowdfund.initialize,
                AuctionCrowdfund.AuctionCrowdfundOptions({
                    name: defaultName,
                    symbol: defaultSymbol,
                    auctionId: auctionId,
                    market: market,
                    nftContract: tokenToBuy,
                    nftTokenId: tokenId,
                    duration: defaultDuration,
                    maximumBid: defaultMaxBid,
                    splitRecipient: defaultSplitRecipient,
                    splitBps: defaultSplitBps,
                    initialContributor: initialContributor,
                    initialDelegate: initialDelegate,
                    gateKeeper: defaultGateKeeper,
                    gateKeeperId: defaultGateKeeperId,
                    governanceOpts: defaultGovernanceOpts
                })
            )
        ))));
    }

    function _contribute(AuctionCrowdfund pb, address contributor, uint256 amount) private {
        vm.deal(contributor, amount);
        vm.prank(contributor);
        pb.contribute{ value: amount }(contributor, "");
    }

    function _contribute(AuctionCrowdfund pb, address contributor, address delegate, uint256 amount) private {
        uint256 previousTotalContributions = pb.totalContributions();
        vm.deal(contributor, amount);
        vm.prank(contributor);
        _expectEmit0();
        emit Contributed(contributor, amount, delegate, previousTotalContributions);
        pb.contribute{ value: amount }(delegate, "");
    }

    function _outbidExternally(uint256 auctionId) private {
        market.bid
            { value: market.getMinimumBid(auctionId) }
            (auctionId, _randomAddress());
    }
}
