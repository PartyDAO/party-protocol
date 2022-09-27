// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "contracts/crowdfund/RollingAuctionCrowdfund.sol";
import "contracts/globals/Globals.sol";
import "contracts/utils/Proxy.sol";
import "contracts/tokens/ERC721Receiver.sol";
import "./MockPartyFactory.sol";
import "./MockMarketWrapper.sol";

import "../TestUtils.sol";

contract RollingAuctionCrowdfundTest is TestUtils, ERC721Receiver {
    event Won(uint256 bid, Party party);
    event Lost();
    event AuctionUpdated(uint256 newNftTokenId, uint256 newAuctionId);

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
        rollingAuctionCrowdfundImpl = new RollingAuctionCrowdfund(globals);
        market = IMarketWrapper(new MockMarketWrapper());
        nftContract = IERC721(address(MockMarketWrapper(address(market)).nftContract()));
        (auctionId, tokenId) = MockMarketWrapper(address(market)).createAuction(1 ether);

        // Set host
        govOpts.hosts = _toAddressArray(address(this));

        // Create crowdfund
        crowdfund = RollingAuctionCrowdfund(payable(address(new Proxy(
            rollingAuctionCrowdfundImpl,
            abi.encodeCall(
                RollingAuctionCrowdfund.initialize,
                RollingAuctionCrowdfund.RollingAuctionCrowdfundOptions({
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
                    onlyHostCanBid: false,
                    allowedAuctionsMerkleRoot: bytes32(0),
                    governanceOpts: govOpts
                })
            )
        ))));

        // Contribute enough ETH to play with
        vm.deal(address(this), 100 ether);
        crowdfund.contribute{ value: 100 ether }(address(this), "");
    }

    function test_finalizeLoss_rollOverToNextAuction() public onlyForkedIfSet {
        // Bid on the auction
        crowdfund.bid(govOpts, 0);

        _outbid();

        _endAuction();

        _setNextAuction();

        // Move on to next auction
        _expectEmit0();
        emit AuctionUpdated(tokenId, auctionId);
        crowdfund.finalizeOrRollOver(govOpts, tokenId, auctionId, new bytes32[](0));
        assertEq(crowdfund.auctionId(), auctionId);
        assertEq(crowdfund.nftTokenId(), tokenId);
        assertEq(crowdfund.lastBid(), 0);
    }

    function test_finalizeLoss_rollOverToNextAuction_multipleTimes() public onlyForkedIfSet {
        for (uint256 i; i < 5; i++) test_finalizeLoss_rollOverToNextAuction();
    }

    function test_finalizeLoss_rollOverToNextAuction_thenWin() public onlyForkedIfSet {
        test_finalizeLoss_rollOverToNextAuction();

        // Bid on the new auction
        crowdfund.bid(govOpts, 0);

        _endAuction();

        // Finalize and win new auction
        _expectEmit0();
        emit Won(crowdfund.lastBid(), Party(payable(address(partyFactory.mockParty()))));
        Party party = crowdfund.finalizeOrRollOver(govOpts, tokenId, auctionId, new bytes32[](0));
        assertEq(address(nftContract.ownerOf(tokenId)), address(party));
        assertEq(address(crowdfund.party()), address(partyFactory.mockParty()));
    }

    function test_finalizeLoss_revertIfInvalidNextAuction() public onlyForkedIfSet {
        // Bid on the auction
        crowdfund.bid(govOpts, 0);

        _outbid();

        _endAuction();

        // Set allowed next auction to current auction (should revert because invalid).
        crowdfund.setAllowedAuctions(govOpts, keccak256(abi.encodePacked(auctionId, tokenId)), 0);

        // Attempt finalizing and setting next auction to the one that just ended
        vm.expectRevert(abi.encodeWithSelector(
            RollingAuctionCrowdfund.InvalidAuctionIdError.selector
        ));
        crowdfund.finalizeOrRollOver(govOpts, tokenId, auctionId, new bytes32[](0));
    }

    function test_finalizeLoss_revertIfBadNextAuctionError() public onlyForkedIfSet {
        // Bid on the auction
        crowdfund.bid(govOpts, 0);

        _outbid();

        _endAuction();

        // Attempt finalizing and setting next auction to the one that just ended
        vm.expectRevert(abi.encodeWithSelector(
            RollingAuctionCrowdfund.BadNextAuctionError.selector
        ));
        crowdfund.finalizeOrRollOver(govOpts, _randomUint256(), _randomUint256(), new bytes32[](0));
    }

    function test_finalizeLoss_expiredWithoutNFT() public onlyForkedIfSet {
        _endAuction();

        _skipToExpiry();

        _expectEmit0();
        emit Lost();
        vm.prank(_randomAddress());
        crowdfund.finalizeOrRollOver(govOpts, tokenId, auctionId, new bytes32[](0));
        assertEq(address(crowdfund.party()), address(0));
    }

    function test_finalizeWin_ignoresAuctionIdAndTokenId() public onlyForkedIfSet {
        // Bid on the auction
        crowdfund.bid(govOpts, 0);

        _endAuction();

        // Finalize and win auction (with bad `auctionId` and `tokenId`)
        _expectEmit0();
        emit Won(crowdfund.lastBid(), Party(payable(address(partyFactory.mockParty()))));
        Party party =
            crowdfund.finalizeOrRollOver(govOpts, _randomUint256(), _randomUint256(), new bytes32[](0));
        assertEq(address(nftContract.ownerOf(tokenId)), address(party));
        assertEq(address(crowdfund.party()), address(partyFactory.mockParty()));
    }

    function test_finalizeWin_expiredWithNFT() public onlyForkedIfSet {
        // Bid on the auction
        crowdfund.bid(govOpts, 0);

        _endAuction();

        _skipToExpiry();

        _expectEmit0();
        emit Won(crowdfund.lastBid(), Party(payable(address(partyFactory.mockParty()))));
        vm.prank(_randomAddress());
        crowdfund.finalizeOrRollOver(govOpts, tokenId, auctionId, new bytes32[](0));
        assertEq(address(crowdfund.party()), address(partyFactory.mockParty()));
    }

    function test_setAllowedAuctions_onlyHost() public onlyForkedIfSet {
        vm.prank(_randomAddress());
        vm.expectRevert(Crowdfund.OnlyPartyHostError.selector);
        crowdfund.setAllowedAuctions(govOpts, keccak256(abi.encodePacked(auctionId, tokenId)), 0);
    }

    function _setNextAuction() internal virtual {
        (auctionId, tokenId) = MockMarketWrapper(address(market)).createAuction(1 ether);
        crowdfund.setAllowedAuctions(govOpts, keccak256(abi.encodePacked(auctionId, tokenId)), 0);
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