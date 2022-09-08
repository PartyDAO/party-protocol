// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/AuctionCrowdfund.sol";
import "../../contracts/crowdfund/PartyCrowdfund.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/utils/Proxy.sol";
import "../../contracts/proposals/vendor/IZoraAuctionHouse.sol";

import "./MockPartyFactory.sol";
import "./MockParty.sol";
import "../DummyERC721.sol";

import "../TestUtils.sol";

contract ZoraForkedTest is TestUtils, ERC721Receiver {
    event Won(uint256 bid, Party party);
    event Lost();

    // Initialize party contracts
    Globals globals = new Globals(address(this));
    MockPartyFactory partyFactory = new MockPartyFactory();
    MockParty party = partyFactory.mockParty();
    AuctionCrowdfund pbImpl = new PartyBid(globals);
    AuctionCrowdfund pb;

    PartyCrowdfund.FixedGovernanceOpts defaultGovOpts;

    // Initialize Zora contracts
    IZoraAuctionHouse zora =
        IZoraAuctionHouse(0xE468cE99444174Bd3bBBEd09209577d25D1ad673);
    IMarketWrapper zoraMarket =
        IMarketWrapper(0x11c07cE1315a3b92C9755F90cDF40B04b88c5731);
    DummyERC721 nftContract = new DummyERC721();
    uint256 tokenId = nftContract.mint(address(this));
    uint256 auctionId;

    constructor() onlyForked {
        // Initialize PartyFactory for creating parties after a successful crowdfund.
        globals.setAddress(
            LibGlobals.GLOBAL_PARTY_FACTORY,
            address(partyFactory)
        );

        // Create a reserve auction on Zora to bid on
        nftContract.approve(address(zora), tokenId);
        auctionId = zora.createAuction(
            tokenId,
            nftContract,
            1 days,
            1 ether,
            payable(address(0)),
            0,
            IERC20(address(0)) // Indicates ETH sale
        );

        // Create a AuctionCrowdfund crowdfund
        pb = AuctionCrowdfund(
            payable(
                address(
                    new Proxy(
                        pbImpl,
                        abi.encodeCall(
                            AuctionCrowdfund.initialize,
                            AuctionCrowdfund.PartyBidOptions({
                                name: "Party",
                                symbol: "PRTY",
                                auctionId: auctionId,
                                market: zoraMarket,
                                nftContract: nftContract,
                                nftTokenId: tokenId,
                                duration: 1 days,
                                maximumBid: type(uint96).max,
                                splitRecipient: payable(address(0)),
                                splitBps: 0,
                                initialContributor: address(this),
                                initialDelegate: address(0),
                                gateKeeper: IGateKeeper(address(0)),
                                gateKeeperId: 0,
                                governanceOpts: defaultGovOpts
                            })
                        )
                    )
                )
            )
        );

        // Contribute ETH used to bid.
        vm.deal(address(this), 1000 ether);
        pb.contribute{value: 1000 ether}(address(this), "");
    }

    // Test creating a crowdfund party around a Zora auction + winning the auction
    function testForked_WinningZoraAuction() external onlyForked {
        // Bid on current Zora auction.
        pb.bid();

        // Check that we are highest bidder.
        uint256 lastBid = pb.lastBid();
        IZoraAuctionHouse.Auction memory auction = zora.auctions(auctionId);
        assertEq(lastBid, auction.amount);
        assertEq(address(payable(pb)), auction.bidder);

        // Wait for the auction to end and check that we won.
        skip(1 days);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Won(lastBid, Party(payable(address(party))));
        pb.finalize(defaultGovOpts);
        assertEq(nftContract.ownerOf(tokenId), address(party));
        assertEq(address(pb.party()), address(party));
        assertTrue(zoraMarket.isFinalized(tokenId));
    }

    function testForked_WinningZoraAuction_finalizeBefore() external onlyForked {
        // Bid on current Zora auction.
        pb.bid();

        // Check that we are highest bidder.
        uint256 lastBid = pb.lastBid();
        IZoraAuctionHouse.Auction memory auction = zora.auctions(auctionId);
        assertEq(lastBid, auction.amount);
        assertEq(address(payable(pb)), auction.bidder);

        // Wait for the auction to end and check that we won.
        skip(1 days);

        // Finalize the auction before `finalize()` is called by the crowdfund.
        zoraMarket.finalize(auctionId);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Won(lastBid, Party(payable(address(party))));
        pb.finalize(defaultGovOpts);
        assertEq(nftContract.ownerOf(tokenId), address(party));
        assertEq(address(pb.party()), address(party));
        assertTrue(zoraMarket.isFinalized(tokenId));
    }

    // Test creating a crowdfund party around a Zora auction + losing the auction
    function testForked_LosingZoraAuction() external onlyForked {
        // Bid on current Zora auction.
        pb.bid();

        // We outbid our own party (sneaky!)
        vm.deal(address(this), 1001 ether);
        (bool success, bytes memory returnData) = address(zora).call{
            value: 1001 ether
        }(
            abi.encodeWithSignature(
                "createBid(uint256,uint256)",
                auctionId,
                1001 ether
            )
        );
        require(success, string(returnData));

        // Wait for the auction to end and check that we lost.
        skip(1 days);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Lost();
        pb.finalize(defaultGovOpts);
        assertEq(address(pb.party()), address(0));
        assertTrue(zoraMarket.isFinalized(tokenId));
    }

    function testForked_LosingZoraAuction_finalizeBefore() external onlyForked {
        // Bid on current Zora auction.
        pb.bid();

        // We outbid our own party (sneaky!)
        vm.deal(address(this), 1001 ether);
        (bool success, bytes memory returnData) = address(zora).call{
            value: 1001 ether
        }(
            abi.encodeWithSignature(
                "createBid(uint256,uint256)",
                auctionId,
                1001 ether
            )
        );
        require(success, string(returnData));

        // Wait for the auction to end and check that we lost.
        skip(1 days);

        // Finalize the auction before `finalize()` is called by the crowdfund.
        zoraMarket.finalize(auctionId);

        // Finalize the crowdfund.
        _expectEmit0();
        emit Lost();
        pb.finalize(defaultGovOpts);
        assertEq(address(pb.party()), address(0));
        assertTrue(zoraMarket.isFinalized(tokenId));
    }
}
