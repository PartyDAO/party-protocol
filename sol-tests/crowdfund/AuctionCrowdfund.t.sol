// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/AuctionCrowdfund.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/utils/Proxy.sol";
import "../../contracts/gatekeepers/AllowListGateKeeper.sol";

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

    event MockMint(address caller, address owner, uint256 amount, address delegate);

    event MockMarketWrapperBid(address bidder, uint256 auctionId, uint256 bidAmount);

    event MockMarketWrapperFinalize(address caller, address winner, uint256 topBid);

    event Burned(address contributor, uint256 ethUsed, uint256 ethOwed, uint256 votingPower);
    event Contributed(
        address sender,
        address contributor,
        uint256 amount,
        address delegate,
        uint256 previousTotalContributions
    );
    event Won(uint256 bid, Party party);
    event Lost();

    string defaultName = "AuctionCrowdfund";
    string defaultSymbol = "PBID";
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
        uint96 initialContribution,
        bool onlyHostCanBid,
        IGateKeeper gateKeeper,
        bytes12 gateKeeperId,
        address[] memory hosts
    ) private returns (AuctionCrowdfund cf) {
        defaultGovernanceOpts.hosts = hosts;
        cf = AuctionCrowdfund(
            payable(
                address(
                    new Proxy{ value: initialContribution }(
                        auctionCrowdfundImpl,
                        abi.encodeCall(
                            AuctionCrowdfund.initialize,
                            AuctionCrowdfundBase.AuctionCrowdfundOptions({
                                name: defaultName,
                                symbol: defaultSymbol,
                                customizationPresetId: 0,
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
                                minContribution: 0,
                                maxContribution: type(uint96).max,
                                gateKeeper: gateKeeper,
                                gateKeeperId: gateKeeperId,
                                onlyHostCanBid: onlyHostCanBid,
                                governanceOpts: defaultGovernanceOpts
                            })
                        )
                    )
                )
            )
        );
    }

    function _createCrowdfund(
        uint256 auctionId,
        uint256 tokenId,
        uint96 initialContribution
    ) private returns (AuctionCrowdfund cf) {
        return
            _createCrowdfund(
                auctionId,
                tokenId,
                initialContribution,
                false,
                defaultGateKeeper,
                defaultGateKeeperId,
                defaultGovernanceOpts.hosts
            );
    }

    function _createExpectedPartyOptions(
        uint256 finalPrice
    ) private view returns (Party.PartyOptions memory opts) {
        return
            Party.PartyOptions({
                name: defaultName,
                symbol: defaultSymbol,
                customizationPresetId: 0,
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
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        _contribute(cf, contributor, delegate, 1e18);
        // Bid on the auction.
        _expectEmit0();
        emit MockMarketWrapperBid(address(cf), auctionId, 1337);
        cf.bid(defaultGovernanceOpts, 0);
        // End the auction.
        _expectEmit0();
        emit MockMarketWrapperFinalize(address(cf), address(cf), 1337);
        market.endAuction(auctionId);
        // Finalize the crowdfund.
        _expectEmit0();
        emit MockPartyFactoryCreateParty(
            address(cf),
            address(cf),
            _createExpectedPartyOptions(1337),
            _toERC721Array(tokenToBuy),
            _toUint256Array(tokenId)
        );
        Party party_ = cf.finalize(defaultGovernanceOpts);
        assertEq(address(party_), address(party));
        // Burn contributor's NFT, mock minting governance tokens and returning
        // unused contribution.
        _expectEmit0();
        emit MockMint(address(cf), contributor, 1337, delegate);
        _expectEmit0();
        emit Burned(contributor, 1337, 1e18 - 1337, 1337);
        cf.burn(contributor);
        assertEq(contributor.balance, 1e18 - 1337);
    }

    function test_canBidWithCustomAmountAsHost() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(
            auctionId,
            tokenId,
            0,
            false,
            IGateKeeper(address(0)),
            "",
            _toAddressArray(address(this))
        );
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        _contribute(cf, contributor, delegate, 1e18);
        // Expect revert if not host.
        vm.expectRevert(Crowdfund.OnlyPartyHostError.selector);
        vm.prank(_randomAddress());
        cf.bid(1e18, defaultGovernanceOpts, 0);
        // Bid on the auction with a custom amount as host.
        cf.bid(1e18, defaultGovernanceOpts, 0);
    }

    function test_cannotReinitialize() external {
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        vm.expectRevert(abi.encodeWithSelector(Implementation.OnlyConstructorError.selector));
        AuctionCrowdfundBase.AuctionCrowdfundOptions memory opts;
        cf.initialize(opts);
    }

    function test_canRefundIfCrowdfundLosesAndNoBidsMade() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        market.endAuction(auctionId);
        // Expire and finalize the crowdfund.
        skip(defaultDuration);
        Party party_ = cf.finalize(defaultGovernanceOpts);
        assertEq(address(party_), address(0));
        // Burn contributor's NFT, which should refund all contributed ETH.
        _expectEmit0();
        emit Burned(contributor, 0, 1e18, 0);
        cf.burn(contributor);
        assertEq(contributor.balance, 1e18);
    }

    function test_canRefundIfCrowdfundLosesWithBidsMade_notFinalized() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        // Bid on the auction.
        cf.bid(defaultGovernanceOpts, 0);
        // Outbid externally so we're losing.
        _outbidExternally(auctionId);
        // End the auction.
        market.endAuction(auctionId);
        // Expire and finalize the crowdfund.
        skip(defaultDuration);
        Party party_ = cf.finalize(defaultGovernanceOpts);
        assertEq(address(party_), address(0));
        // Burn contributor's NFT, which should refund all contributed ETH.
        _expectEmit0();
        emit Burned(contributor, 0, 1e18, 0);
        cf.burn(contributor);
        assertEq(contributor.balance, 1e18);
    }

    function test_canRefundIfCrowdfundLosesWithBidsMade_finalized() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        // Bid on the auction.
        cf.bid(defaultGovernanceOpts, 0);
        // Outbid externally so we're losing.
        _outbidExternally(auctionId);
        // End the auction and finalize it.
        market.endAuction(auctionId);
        market.finalize(auctionId);
        // Expire and finalize the crowdfund.
        skip(defaultDuration);
        Party party_ = cf.finalize(defaultGovernanceOpts);
        assertEq(address(party_), address(0));
        // Burn contributor's NFT, which should refund all contributed ETH.
        _expectEmit0();
        emit Burned(contributor, 0, 1e18, 0);
        cf.burn(contributor);
        assertEq(contributor.balance, 1e18);
    }

    function test_canWinEvenIfExpiredIfAlsoTopBidder() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        // Bid on the auction.
        cf.bid(defaultGovernanceOpts, 0);
        // Expire and finalize the crowdfund.
        skip(defaultDuration);
        assertEq(uint8(cf.getCrowdfundLifecycle()), uint8(Crowdfund.CrowdfundLifecycle.Expired));
        // End the auction.
        market.endAuction(auctionId);
        // Finalize the crowdfund.
        Party party_ = cf.finalize(defaultGovernanceOpts);
        assertEq(address(party_), address(party));
        // Burn contributor's NFT, which should refund unused ETH and mint voting power.
        _expectEmit0();
        emit Burned(contributor, 1337, 1e18 - 1337, 1337);
        cf.burn(contributor);
        assertEq(contributor.balance, 1e18 - 1337);
    }

    function test_cannotBidAfterFinalize() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        // Bid on the auction.
        cf.bid(defaultGovernanceOpts, 0);
        // End the auction.
        market.endAuction(auctionId);
        // Finalize the crowdfund.
        Party party_ = cf.finalize(defaultGovernanceOpts);
        assertEq(address(party_), address(party));
        // Try to bid with the crowdfund again.
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdfund.WrongLifecycleError.selector,
                Crowdfund.CrowdfundLifecycle.Won
            )
        );
        cf.bid(defaultGovernanceOpts, 0);
    }

    function test_cannotFinalizeTwice() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        // Bid on the auction.
        cf.bid(defaultGovernanceOpts, 0);
        // End the auction.
        market.endAuction(auctionId);
        // Finalize the crowdfund.
        Party party_ = cf.finalize(defaultGovernanceOpts);
        assertEq(address(party_), address(party));
        // Try to finalize the crowdfund again.
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdfund.WrongLifecycleError.selector,
                Crowdfund.CrowdfundLifecycle.Won
            )
        );
        cf.finalize(defaultGovernanceOpts);
    }

    function test_cannotFinalizeTooEarlyWithNoBids() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        // Finalize the crowdfund early.
        vm.expectRevert("AUCTION_NOT_ENDED");
        cf.finalize(defaultGovernanceOpts);
    }

    function test_canFinalizeIfExpiredBeforeAuctionEnds_noBids() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        market.endAuction(auctionId);
        // Finalize the crowdfund.
        _expectEmit0();
        emit Lost();
        cf.finalize(defaultGovernanceOpts);
    }

    function test_canFinalizeIfExpiredAfterAuctionEnds_noBids() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        skip(defaultDuration);
        market.endAuction(auctionId);
        _expectEmit0();
        emit Lost();
        // Finalize the crowdfund.
        cf.finalize(defaultGovernanceOpts);
    }

    function test_canFinalizeIfExpiredAndAuctionFinalized_noBids() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        skip(defaultDuration);
        market.endAuction(auctionId);
        market.finalize(auctionId);
        _expectEmit0();
        emit Lost();
        // Finalize the crowdfund.
        cf.finalize(defaultGovernanceOpts);
    }

    function test_cannotFinalizeIfExpiredBeforeAuctionEndsIfHighestBidder() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        // Place a bid.
        cf.bid(defaultGovernanceOpts, 0);
        // Expire the CF.
        skip(defaultDuration);
        // Check that the CF is highest bidder.
        assertTrue(market.getCurrentHighestBidder(auctionId) == address(cf));
        // Check that the CF is expired.
        assertTrue(cf.getCrowdfundLifecycle() == Crowdfund.CrowdfundLifecycle.Expired);
        // Finalize the crowdfund.
        vm.expectRevert("AUCTION_NOT_ENDED");
        cf.finalize(defaultGovernanceOpts);
    }

    function test_canFinalizeIfExpiredBeforeAuctionEndsIfNotHighestBidder() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        // Place a bid.
        cf.bid(defaultGovernanceOpts, 0);
        // Get outbid.
        _outbidExternally(auctionId);
        // Expire the CF.
        skip(defaultDuration);
        // Check that the CF is not highest bidder.
        assertTrue(market.getCurrentHighestBidder(auctionId) != address(cf));
        // Check that the CF is expired.
        assertTrue(cf.getCrowdfundLifecycle() == Crowdfund.CrowdfundLifecycle.Expired);
        // Finalize the crowdfund.
        cf.finalize(defaultGovernanceOpts);
        assertTrue(cf.getCrowdfundLifecycle() == Crowdfund.CrowdfundLifecycle.Lost);
    }

    function test_canFinalizeIfExpiredAfterAuctionEnds_withBids() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        uint256 bid = market.getMinimumBid(auctionId);
        // Place a bid.
        cf.bid(defaultGovernanceOpts, 0);
        // Expire the CF.
        skip(defaultDuration);
        // End the auction.
        market.endAuction(auctionId);
        _expectEmit0();
        emit Won(bid, Party(payable(address(party))));
        cf.finalize(defaultGovernanceOpts);
    }

    function test_canFinalizeIfExpiredAndNeverBid() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        market.getMinimumBid(auctionId);
        // Expire the CF.
        skip(defaultDuration);
        _expectEmit0();
        emit Lost();
        cf.finalize(defaultGovernanceOpts);
    }

    function test_cannotReenterFinalize() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        // Bid on the auction.
        cf.bid(defaultGovernanceOpts, 0);
        // End the auction.
        market.endAuction(auctionId);
        // Set up a callback to reenter finalize().
        market.setCallback(address(cf), abi.encodeCall(cf.finalize, defaultGovernanceOpts), 0);
        // Finalize the crowdfund.
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdfund.WrongLifecycleError.selector,
                Crowdfund.CrowdfundLifecycle.Busy
            )
        );
        cf.finalize(defaultGovernanceOpts);
    }

    function test_cannotReenterBid() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        // Set up a callback to reenter bid().
        market.setCallback(address(cf), abi.encodeWithSignature("bid()"), 0);
        // Bid on the auction.
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdfund.WrongLifecycleError.selector,
                Crowdfund.CrowdfundLifecycle.Busy
            )
        );
        cf.bid(defaultGovernanceOpts, 0);
    }

    function test_cannotReenterContributeThroughBid() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        // Set up a callback to reenter bid().
        market.setCallback(address(cf), abi.encodeCall(cf.contribute, (contributor, "")), 1);
        // Bid on the auction.
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdfund.WrongLifecycleError.selector,
                Crowdfund.CrowdfundLifecycle.Busy
            )
        );
        cf.bid(defaultGovernanceOpts, 0);
    }

    function test_cannotReenterContributeThroughFinalize() external {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        // Bid on the auction.
        cf.bid(defaultGovernanceOpts, 0);
        // End the auction.
        market.endAuction(auctionId);
        // Set up a callback to reenter contribute().
        market.setCallback(address(cf), abi.encodeCall(cf.contribute, (contributor, "")), 1);
        // Finalize the crowdfund.
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdfund.WrongLifecycleError.selector,
                Crowdfund.CrowdfundLifecycle.Busy
            )
        );
        cf.finalize(defaultGovernanceOpts);
    }

    function test_onlyHostCanBid() public {
        address host = _randomAddress();
        address contributor = _randomAddress();

        // Create a AuctionCrowdfund instance with `onlyHost` enabled.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(0);
        AuctionCrowdfund cf = _createCrowdfund(
            auctionId,
            tokenId,
            0,
            true,
            IGateKeeper(address(0)),
            "",
            _toAddressArray(host)
        );

        // Contributor contributes.
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(contributor, abi.encode(new bytes32[](0)));

        // Skip past exipry.
        vm.warp(cf.expiry());

        // Bid, expect revert because we are not a host.
        vm.expectRevert(Crowdfund.OnlyPartyHostError.selector);
        cf.bid(defaultGovernanceOpts, 0);

        // Bid as a contributor, but expect a revert because they are not a host.
        vm.expectRevert(Crowdfund.OnlyPartyHostError.selector);
        vm.prank(contributor);
        cf.bid(defaultGovernanceOpts, 0);

        // Bid as the host, but expect a revert because the CF is expired.
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdfund.WrongLifecycleError.selector,
                Crowdfund.CrowdfundLifecycle.Expired
            )
        );
        vm.prank(host);
        cf.bid(defaultGovernanceOpts, 0);
    }

    function test_onlyHostCanBidWithGatekeeperSet() public {
        address host = _randomAddress();
        address contributor = _randomAddress();

        // Create a AuctionCrowdfund instance with onlyHostCanBid and gatekeeper enabled.
        AllowListGateKeeper gateKeeper = new AllowListGateKeeper();
        bytes32 contributorHash = keccak256(abi.encodePacked(contributor));
        bytes12 gateKeeperId = gateKeeper.createGate(contributorHash);
        (uint256 auctionId, uint256 tokenId) = market.createAuction(0);
        AuctionCrowdfund cf = _createCrowdfund(
            auctionId,
            tokenId,
            0,
            true,
            gateKeeper,
            gateKeeperId,
            _toAddressArray(host)
        );

        // Contributor contributes.
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(contributor, abi.encode(new bytes32[](0)));

        // Skip past exipry.
        vm.warp(cf.expiry());

        // Bid, expect revert because we are not a host or contributor.
        vm.expectRevert(Crowdfund.OnlyPartyHostError.selector);
        cf.bid(defaultGovernanceOpts, 0);

        // Bid as a contributor, but expect a revert because onlyHost is on.
        vm.expectRevert(abi.encodeWithSelector(Crowdfund.OnlyPartyHostError.selector));
        vm.prank(contributor);
        cf.bid(defaultGovernanceOpts, 0);

        // Bid as the host, but expect a revert because the CF is expired.
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdfund.WrongLifecycleError.selector,
                Crowdfund.CrowdfundLifecycle.Expired
            )
        );
        vm.prank(host);
        cf.bid(defaultGovernanceOpts, 0);
    }

    function test_onlyContributorCanBid() public {
        address host = _randomAddress();
        address contributor = _randomAddress();

        // Create a AuctionCrowdfund instance with a gatekeeper enabled.
        AllowListGateKeeper gateKeeper = new AllowListGateKeeper();
        bytes32 contributorHash = keccak256(abi.encodePacked(contributor));
        bytes12 gateKeeperId = gateKeeper.createGate(contributorHash);
        (uint256 auctionId, uint256 tokenId) = market.createAuction(0);
        AuctionCrowdfund cf = _createCrowdfund(
            auctionId,
            tokenId,
            0,
            false,
            gateKeeper,
            gateKeeperId,
            _toAddressArray(host)
        );

        // Contributor contributes.
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(contributor, abi.encode(new bytes32[](0)));

        // Skip past expiry.
        vm.warp(cf.expiry());

        // Bid, expect revert because we are not a contributor.
        vm.expectRevert(Crowdfund.OnlyContributorError.selector);
        cf.bid(defaultGovernanceOpts, 0);

        // Bid as a contributor, but expect a revert because the CF is expired.
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdfund.WrongLifecycleError.selector,
                Crowdfund.CrowdfundLifecycle.Expired
            )
        );
        vm.prank(contributor);
        cf.bid(defaultGovernanceOpts, 0);

        // Bid as the host, but expect a revert because the host is not a contributor.
        vm.expectRevert(Crowdfund.OnlyContributorError.selector);
        vm.prank(host);
        cf.bid(defaultGovernanceOpts, 0);
    }

    function test_gettingNFTForFreeTriggersLostToRefund() public {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a AuctionCrowdfund instance.
        AuctionCrowdfund cf = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        _contribute(cf, contributor, 1e18);
        // Acquire the NFT to gift.
        _outbidExternally(auctionId);
        skip(defaultDuration);
        market.endAuction(auctionId);
        market.finalize(auctionId);
        // Gift the NFT to the crowdfund.
        IERC721 token = IERC721(market.nftContract());
        address winner = token.ownerOf(tokenId);
        vm.prank(winner);
        token.transferFrom(winner, address(cf), tokenId);
        assertEq(token.ownerOf(tokenId), address(cf));
        // Finalize the crowdfund.
        _expectEmit0();
        emit Lost();
        cf.finalize(defaultGovernanceOpts);
    }

    function test_creation_initialContribution() external {
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        uint256 initialContribution = _randomRange(1, 1 ether);
        address initialContributor = _randomAddress();
        address initialDelegate = _randomAddress();
        vm.deal(address(this), initialContribution);
        emit Contributed(
            address(this),
            initialContributor,
            initialContribution,
            initialDelegate,
            0
        );
        AuctionCrowdfund(
            payable(
                address(
                    new Proxy{ value: initialContribution }(
                        auctionCrowdfundImpl,
                        abi.encodeCall(
                            AuctionCrowdfund.initialize,
                            AuctionCrowdfundBase.AuctionCrowdfundOptions({
                                name: defaultName,
                                symbol: defaultSymbol,
                                customizationPresetId: 0,
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
                                minContribution: 0,
                                maxContribution: type(uint96).max,
                                gateKeeper: defaultGateKeeper,
                                gateKeeperId: defaultGateKeeperId,
                                onlyHostCanBid: false,
                                governanceOpts: defaultGovernanceOpts
                            })
                        )
                    )
                )
            )
        );
    }

    function _contribute(AuctionCrowdfund cf, address contributor, uint256 amount) private {
        vm.deal(contributor, amount);
        vm.prank(contributor);
        cf.contribute{ value: amount }(contributor, "");
    }

    function _contribute(
        AuctionCrowdfund cf,
        address contributor,
        address delegate,
        uint256 amount
    ) private {
        uint256 previousTotalContributions = cf.totalContributions();
        _expectEmit0();
        emit Contributed(contributor, contributor, amount, delegate, previousTotalContributions);
        vm.deal(contributor, amount);
        vm.prank(contributor);
        cf.contribute{ value: amount }(delegate, "");
    }

    function _outbidExternally(uint256 auctionId) private {
        market.bid{ value: market.getMinimumBid(auctionId) }(auctionId, _randomAddress());
    }
}
