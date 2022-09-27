// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "./RollingAuctionCrowdfund.t.sol";
import "contracts/vendor/markets/INounsAuctionHouse.sol";

contract RollingNounsCrowdfundForkedTest is RollingAuctionCrowdfundTest {
    INounsAuctionHouse nounsAuctionHouse;

    constructor() {
        onlyRunIfForked = true;
    }

    function setUp() public override onlyForkedIfSet() {
        // Setup state
        globals = new Globals(address(this));
        partyFactory = new MockPartyFactory();
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));
        rollingAuctionCrowdfundImpl = new RollingAuctionCrowdfund(globals);
        market = IMarketWrapper(0x9319DAd8736D752C5c72DB229f8e1b280DC80ab1);
        nounsAuctionHouse = INounsAuctionHouse(0x830BD73E4184ceF73443C15111a1DF14e495C706);
        nftContract = nounsAuctionHouse.nouns();
        (tokenId, , , , , ) = nounsAuctionHouse.auction();
        auctionId = tokenId;

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
                    duration: 7 days,
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
        vm.deal(address(this), 1000 ether);
        crowdfund.contribute{ value: 1000 ether }(address(this), "");
    }

    function _setNextAuction() internal override {
        market.finalize(auctionId);
        (tokenId, , , , , ) = nounsAuctionHouse.auction();
        auctionId = tokenId;
        crowdfund.setAllowedAuctions(govOpts, keccak256(abi.encodePacked(auctionId, tokenId)), 0);
    }

    function _endAuction() internal override {
        // Skip to end of auction
        skip(1 days);
    }

    function _skipToExpiry() internal override {
        skip(7 days);
        assertEq(uint8(crowdfund.getCrowdfundLifecycle()), uint8(Crowdfund.CrowdfundLifecycle.Expired));
    }

    function _outbid() internal override {
        // Outbid the crowdfund.
        vm.deal(address(this), 1001 ether);
        nounsAuctionHouse.createBid{ value: 1001 ether }(tokenId);
    }
}