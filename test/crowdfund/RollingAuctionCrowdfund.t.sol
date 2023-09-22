// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { Clones } from "openzeppelin/contracts/proxy/Clones.sol";

import "contracts/crowdfund/RollingAuctionCrowdfund.sol";
import "contracts/renderers/RendererStorage.sol";
import "contracts/globals/Globals.sol";
import "contracts/tokens/ERC721Receiver.sol";
import "./MockPartyFactory.sol";
import "./MockMarketWrapper.sol";

import "../TestUtils.sol";

contract RollingAuctionCrowdfundTest is TestUtils, ERC721Receiver {
    using Clones for address;

    event Won(uint256 bid, Party party);
    event Lost();
    event AuctionUpdated(uint256 nextNftTokenId, uint256 nextAuctionId, uint256 nextMaximumBid);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    bool onlyRunIfForked;

    Globals globals;
    RollingAuctionCrowdfund rollingAuctionCrowdfundImpl;
    RollingAuctionCrowdfund crowdfund;
    MockPartyFactory partyFactory;
    IMarketWrapper market;
    IERC721 nftContract;
    uint256 tokenId;
    uint256 auctionId;

    Crowdfund.FixedGovernanceOpts govOpts;
    ProposalStorage.ProposalEngineOpts proposalEngineOpts;

    // This is for other test inheriting from this test; this can be ignored for
    // this file as it will always be false.
    modifier onlyForkedIfSet() {
        if (onlyRunIfForked && block.number < 1e6) {
            return;
        }
        _;
    }

    function setUp() public virtual onlyForkedIfSet {
        // Setup state
        globals = new Globals(address(this));
        globals.setAddress(
            LibGlobals.GLOBAL_RENDERER_STORAGE,
            address(new RendererStorage(address(this)))
        );
        partyFactory = new MockPartyFactory();
        rollingAuctionCrowdfundImpl = new RollingAuctionCrowdfund(globals);
        market = IMarketWrapper(new MockMarketWrapper());
        nftContract = IERC721(address(MockMarketWrapper(address(market)).nftContract()));
        _getAuction();

        // Set host
        govOpts.hosts = _toAddressArray(address(this));
        govOpts.partyFactory = partyFactory;
    }

    function _createCrowdfund() internal {
        _createCrowdfund(bytes32(0));
    }

    function _createCrowdfund(bytes32 allowedAuctionsMerkleRoot) internal {
        // Create crowdfund
        crowdfund = RollingAuctionCrowdfund(payable(address(rollingAuctionCrowdfundImpl).clone()));
        crowdfund.initialize(
            AuctionCrowdfundBase.AuctionCrowdfundOptions({
                name: "Crowfund",
                symbol: "CF",
                customizationPresetId: 0,
                auctionId: auctionId,
                market: market,
                nftContract: nftContract,
                nftTokenId: tokenId,
                duration: 2 days,
                maximumBid: type(uint96).max,
                splitRecipient: payable(address(0)),
                splitBps: 0,
                initialContributor: address(this),
                initialDelegate: address(this),
                minContribution: 0,
                maxContribution: type(uint96).max,
                gateKeeper: IGateKeeper(address(0)),
                gateKeeperId: 0,
                onlyHostCanBid: false,
                governanceOpts: govOpts,
                proposalEngineOpts: proposalEngineOpts
            }),
            allowedAuctionsMerkleRoot
        );

        // Contribute enough ETH to play with
        vm.deal(address(this), 100 ether);
        crowdfund.contribute{ value: 100 ether }(address(this), "");
    }

    function test_finalizeLoss_rollOverToNextAuction_onlyAllowedAuctions() public onlyForkedIfSet {
        // Set allowed next auctions.
        (uint256 nextAuctionId, uint256 nextTokenId) = _getNextAuction();
        _createCrowdfund(keccak256(abi.encodePacked(bytes32(0), nextAuctionId, nextTokenId)));

        // Bid on the auction
        crowdfund.bid(govOpts, proposalEngineOpts, 0);

        _outbid();

        _endAuction();

        // Move on to next auction
        _expectEmit0();
        emit AuctionUpdated(nextTokenId, nextAuctionId, 1 ether);
        // Anyone can call rolling over to next auction as long as it's allowed.
        vm.prank(_randomAddress());
        crowdfund.finalizeOrRollOver(
            RollingAuctionCrowdfund.RollOverArgs({
                nextNftTokenId: nextTokenId,
                nextAuctionId: nextAuctionId,
                nextMaximumBid: 1 ether,
                proof: new bytes32[](0),
                hostIndex: 0
            }),
            govOpts,
            proposalEngineOpts
        );
        assertEq(crowdfund.auctionId(), nextAuctionId);
        assertEq(crowdfund.nftTokenId(), nextTokenId);
        assertEq(crowdfund.maximumBid(), 1 ether);
        assertEq(crowdfund.lastBid(), 0);
    }

    function test_finalizeLoss_rollOverToNextAuction_hostChoosesAny() public onlyForkedIfSet {
        _createCrowdfund();

        // Bid on the auction
        crowdfund.bid(govOpts, proposalEngineOpts, 0);

        _outbid();

        _endAuction();

        // Set allowed next auctions.
        (auctionId, tokenId) = _getNextAuction();

        // Move on to next auction
        _expectEmit0();
        emit AuctionUpdated(tokenId, auctionId, 1 ether);
        // Only host can call rolling over to next auction.
        crowdfund.finalizeOrRollOver(
            RollingAuctionCrowdfund.RollOverArgs({
                nextNftTokenId: tokenId,
                nextAuctionId: auctionId,
                nextMaximumBid: 1 ether,
                proof: new bytes32[](0),
                hostIndex: 0
            }),
            govOpts,
            proposalEngineOpts
        );
        assertEq(crowdfund.auctionId(), auctionId);
        assertEq(crowdfund.nftTokenId(), tokenId);
        assertEq(crowdfund.maximumBid(), 1 ether);
        assertEq(crowdfund.lastBid(), 0);
    }

    function test_finalizeLoss_rollOverToNextAuction_thenWin() public onlyForkedIfSet {
        test_finalizeLoss_rollOverToNextAuction_hostChoosesAny();

        // Bid on the new auction
        crowdfund.bid(govOpts, proposalEngineOpts, 0);

        _endAuction();

        // Finalize and win new auction
        _expectEmit0();
        emit Won(crowdfund.lastBid(), Party(payable(address(partyFactory.mockParty()))));
        _expectEmit0();
        emit BatchMetadataUpdate(0, type(uint256).max);
        Party party = crowdfund.finalizeOrRollOver(
            RollingAuctionCrowdfund.RollOverArgs({
                nextNftTokenId: tokenId,
                nextAuctionId: auctionId,
                nextMaximumBid: type(uint96).max,
                proof: new bytes32[](0),
                hostIndex: 0
            }),
            govOpts,
            proposalEngineOpts
        );
        assertEq(address(nftContract.ownerOf(tokenId)), address(party));
        assertEq(address(crowdfund.party()), address(partyFactory.mockParty()));
    }

    function test_finalizeLoss_rollOverToNextAuction_maximumBidCannotBeLowerThanMinimumBid()
        public
        onlyForkedIfSet
    {
        _createCrowdfund();

        // Bid on the auction
        crowdfund.bid(govOpts, proposalEngineOpts, 0);

        _outbid();

        _endAuction();

        // Set allowed next auctions.
        (auctionId, tokenId) = _getNextAuction();

        // Move on to next auction with a maximum bid that is lower than the minimum bid
        uint256 minimumBid = market.getMinimumBid(auctionId);
        uint256 nextMaximumBid = minimumBid - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                AuctionCrowdfundBase.MinimumBidExceedsMaximumBidError.selector,
                minimumBid,
                nextMaximumBid
            )
        );
        crowdfund.finalizeOrRollOver(
            RollingAuctionCrowdfund.RollOverArgs({
                nextNftTokenId: tokenId,
                nextAuctionId: auctionId,
                nextMaximumBid: uint96(nextMaximumBid),
                proof: new bytes32[](0),
                hostIndex: 0
            }),
            govOpts,
            proposalEngineOpts
        );
    }

    function test_finalizeLoss_revertIfInvalidNextAuction() public onlyForkedIfSet {
        _createCrowdfund();

        // Bid on the auction
        crowdfund.bid(govOpts, proposalEngineOpts, 0);

        _outbid();

        _endAuction();

        // Attempt finalizing and setting next auction to the one that just ended
        vm.expectRevert(
            abi.encodeWithSelector(AuctionCrowdfundBase.InvalidAuctionIdError.selector)
        );
        crowdfund.finalizeOrRollOver(
            RollingAuctionCrowdfund.RollOverArgs({
                nextNftTokenId: tokenId,
                nextAuctionId: auctionId,
                nextMaximumBid: type(uint96).max,
                proof: new bytes32[](0),
                hostIndex: 0
            }),
            govOpts,
            proposalEngineOpts
        );
    }

    function test_finalizeLoss_revertIfBadNextAuctionError() public onlyForkedIfSet {
        _createCrowdfund(_randomBytes32());

        // Bid on the auction
        crowdfund.bid(govOpts, proposalEngineOpts, 0);

        _outbid();

        _endAuction();

        // Attempt finalizing and setting next auction to the one that just ended
        vm.expectRevert(
            abi.encodeWithSelector(RollingAuctionCrowdfund.BadNextAuctionError.selector)
        );
        crowdfund.finalizeOrRollOver(
            RollingAuctionCrowdfund.RollOverArgs({
                nextNftTokenId: _randomUint256(),
                nextAuctionId: _randomUint256(),
                nextMaximumBid: type(uint96).max,
                proof: new bytes32[](0),
                hostIndex: 0
            }),
            govOpts,
            proposalEngineOpts
        );
    }

    function test_finalizeLoss_expiredWithoutNFT() public onlyForkedIfSet {
        _createCrowdfund();

        _endAuction();

        _skipToExpiry();

        _expectEmit0();
        emit Lost();
        _expectEmit0();
        emit BatchMetadataUpdate(0, type(uint256).max);
        vm.prank(_randomAddress());
        crowdfund.finalizeOrRollOver(
            RollingAuctionCrowdfund.RollOverArgs({
                nextNftTokenId: tokenId,
                nextAuctionId: auctionId,
                nextMaximumBid: type(uint96).max,
                proof: new bytes32[](0),
                hostIndex: 0
            }),
            govOpts,
            proposalEngineOpts
        );
        assertEq(address(crowdfund.party()), address(0));
    }

    function test_finalizeWin_ignoresAuctionIdAndTokenId() public onlyForkedIfSet {
        _createCrowdfund();

        // Bid on the auction
        crowdfund.bid(govOpts, proposalEngineOpts, 0);

        _endAuction();

        // Finalize and win auction (with bad `auctionId` and `tokenId`)
        _expectEmit0();
        emit Won(crowdfund.lastBid(), Party(payable(address(partyFactory.mockParty()))));
        _expectEmit0();
        emit BatchMetadataUpdate(0, type(uint256).max);
        Party party = crowdfund.finalizeOrRollOver(
            RollingAuctionCrowdfund.RollOverArgs({
                nextNftTokenId: _randomUint256(),
                nextAuctionId: _randomUint256(),
                nextMaximumBid: type(uint96).max,
                proof: new bytes32[](0),
                hostIndex: 0
            }),
            govOpts,
            proposalEngineOpts
        );
        assertEq(address(nftContract.ownerOf(tokenId)), address(party));
        assertEq(address(crowdfund.party()), address(partyFactory.mockParty()));
    }

    function test_finalizeWin_expiredWithNFT() public onlyForkedIfSet {
        _createCrowdfund();

        // Bid on the auction
        crowdfund.bid(govOpts, proposalEngineOpts, 0);

        _endAuction();

        _skipToExpiry();

        _expectEmit0();
        emit Won(crowdfund.lastBid(), Party(payable(address(partyFactory.mockParty()))));
        _expectEmit0();
        emit BatchMetadataUpdate(0, type(uint256).max);
        vm.prank(_randomAddress());
        crowdfund.finalizeOrRollOver(
            RollingAuctionCrowdfund.RollOverArgs({
                nextNftTokenId: tokenId,
                nextAuctionId: auctionId,
                nextMaximumBid: type(uint96).max,
                proof: new bytes32[](0),
                hostIndex: 0
            }),
            govOpts,
            proposalEngineOpts
        );
        assertEq(address(crowdfund.party()), address(partyFactory.mockParty()));
    }

    function _getAuction() internal virtual {
        (auctionId, tokenId) = MockMarketWrapper(address(market)).createAuction(1 ether);
    }

    function _getNextAuction()
        internal
        virtual
        returns (uint256 nextAuctionId, uint256 nextTokenId)
    {
        (nextAuctionId, nextTokenId) = MockMarketWrapper(address(market)).createAuction(1 ether);
    }

    function _endAuction() internal virtual {
        MockMarketWrapper(address(market)).endAuction(auctionId);
        MockMarketWrapper(address(market)).finalize(auctionId);
    }

    function _skipToExpiry() internal virtual {
        skip(2 days);
        assertEq(
            uint8(crowdfund.getCrowdfundLifecycle()),
            uint8(Crowdfund.CrowdfundLifecycle.Expired)
        );
    }

    function _outbid() internal virtual {
        // Outbid the crowdfund.
        vm.deal(address(this), 101 ether);
        MockMarketWrapper(address(market)).bid{ value: 101 ether }(
            auctionId,
            payable(address(this))
        );
    }

    receive() external payable {}
}
