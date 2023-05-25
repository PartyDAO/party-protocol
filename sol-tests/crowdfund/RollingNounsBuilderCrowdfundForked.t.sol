// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "./RollingAuctionCrowdfund.t.sol";
import "contracts/vendor/markets/INounsBuilderAuctionHouse.sol";
import "contracts/market-wrapper/NounsBuilderMarketWrapper.sol";

contract RollingNounsBuilderCrowdfundForkedTest is RollingAuctionCrowdfundTest {
    INounsBuilderAuctionHouse nounsBuilderAuctionHouse;

    constructor() {
        onlyRunIfForked = true;
    }

    function setUp() public override onlyForkedIfSet {
        // Setup state
        globals = new Globals(address(this));
        partyFactory = new MockPartyFactory();
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));
        rollingAuctionCrowdfundImpl = new RollingAuctionCrowdfund(globals);
        market = IMarketWrapper(new NounsBuilderMarketWrapper(0x43790fe6bd46b210eb27F01306C1D3546AEB8C1b));
        nounsBuilderAuctionHouse = INounsBuilderAuctionHouse(0x43790fe6bd46b210eb27F01306C1D3546AEB8C1b);
        nftContract = nounsBuilderAuctionHouse.token();
        _getAuction();

        // Set host
        govOpts.hosts = _toAddressArray(address(this));

        // Create crowdfund
        crowdfund = RollingAuctionCrowdfund(
            payable(
                address(
                    new Proxy(
                        rollingAuctionCrowdfundImpl,
                        abi.encodeCall(
                            RollingAuctionCrowdfund.initialize,
                            RollingAuctionCrowdfund.RollingAuctionCrowdfundOptions({
                                name: "Crowfund",
                                symbol: "CF",
                                customizationPresetId: 0,
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
                                minContribution: 0,
                                maxContribution: type(uint96).max,
                                gateKeeper: IGateKeeper(address(0)),
                                gateKeeperId: 0,
                                onlyHostCanBid: false,
                                allowedAuctionsMerkleRoot: bytes32(0),
                                governanceOpts: govOpts
                            })
                        )
                    )
                )
            )
        );

        // Contribute enough ETH to play with
        vm.deal(address(this), 1000 ether);
        crowdfund.contribute{ value: 1000 ether }(address(this), "");
    }

    function _getAuction() internal override {
        (tokenId, , , , , ) = nounsBuilderAuctionHouse.auction();
        auctionId = tokenId;
    }

    function _getNextAuction()
        internal
        view
        override
        returns (uint256 nextAuctionId, uint256 nextTokenId)
    {
        // Nouns DAO mints every 10th NFT to the founders.
        uint256 i = (tokenId + 1) % 10 == 0 ? 2 : 1;
        (nextAuctionId, nextTokenId) = (auctionId + i, tokenId + i);
    }

    function _endAuction() internal override {
        // Skip to end of auction
        skip(1 days);
        MockMarketWrapper(address(market)).finalize(auctionId);
    }

    function _skipToExpiry() internal override {
        skip(7 days);
        assertEq(
            uint8(crowdfund.getCrowdfundLifecycle()),
            uint8(Crowdfund.CrowdfundLifecycle.Expired)
        );
    }

    function _outbid() internal override {
        // Outbid the crowdfund.
        vm.deal(address(this), 1001 ether);
        nounsBuilderAuctionHouse.createBid{ value: 1001 ether }(tokenId);
    }
}
