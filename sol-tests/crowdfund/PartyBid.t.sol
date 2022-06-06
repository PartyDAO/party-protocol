// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/PartyBid.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/utils/Proxy.sol";

import "../DummyERC721.sol";
import "../TestUtils.sol";

import "./MockPartyFactory.sol";
import "./MockMarketWrapper.sol";

contract PartyBidTest is Test, TestUtils {
    event MockPartyFactoryCreateParty(
        address caller,
        address authority,
        Party.PartyOptions opts,
        IERC721[] preciousTokens,
        uint256[] preciousTokenIds
    );

    event MockPartyFactoryMint(
        address caller,
        Party party,
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

    string defaultName = 'PartyBid';
    string defaultSymbol = 'PBID';
    uint40 defaultDuration = 60 * 60;
    uint128 defaultMaxBid = 10e18;
    address payable defaultSplitRecipient = payable(0);
    uint16 defaultSplitBps = 0.1e4;
    address defaultInitialDelegate;
    IGateKeeper defaultGateKeeper;
    bytes12 defaultGateKeeperId;
    PartyCrowdfund.FixedGovernanceOpts defaultGovernanceOpts;

    Globals globals = new Globals(address(this));
    MockPartyFactory partyFactory = new MockPartyFactory();
    MockMarketWrapper market = new MockMarketWrapper();
    DummyERC721 tokenToBuy;
    PartyBid partyBidImpl;
    Party party;

    constructor() {
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));
        market = new MockMarketWrapper();
        partyFactory = new MockPartyFactory();
        tokenToBuy = market.nftContract();
        party = partyFactory.mockParty();
        partyBidImpl = new PartyBid(globals);
    }

    function setUp() public {
    }

    function _createCrowdfund(
        uint256 auctionId,
        uint256 tokenId,
        uint128 initialContribution
    )
        private
        returns (PartyBid pb)
    {
        pb = PartyBid(payable(address(new Proxy{ value: initialContribution }(
            partyBidImpl,
            abi.encodeCall(
                PartyBid.initialize,
                PartyBid.PartyBidOptions({
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

    function testHappyPath() public {
        // Create a token and auction with min bid of 1337 wei.
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);
        // Create a PartyBid instance.
        PartyBid pb = _createCrowdfund(auctionId, tokenId, 0);
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        pb.contribute{ value: 1e18 }(delegate, "");
        // Bid on the auction.
        vm.expectEmit(false, false, false, true);
        emit MockMarketWrapperBid(address(pb), auctionId, 1337);
        pb.bid();
        // End the auction.
        vm.expectEmit(false, false, false, true);
        emit MockMarketWrapperFinalize(address(pb), address(pb), 1337);
        market.mockEndAuction(auctionId);
        // Finalize the PartyBid.
        vm.expectEmit(false, false, false, true);
        emit MockPartyFactoryCreateParty(
            address(pb),
            address(pb),
            Party.PartyOptions({
                name: pb.name(),
                symbol: pb.symbol(),
                governance: PartyGovernance.GovernanceOpts({
                    hosts: defaultGovernanceOpts.hosts,
                    voteDuration: defaultGovernanceOpts.voteDuration,
                    executionDelay: defaultGovernanceOpts.executionDelay,
                    passThresholdBps: defaultGovernanceOpts.passThresholdBps,
                    totalVotingPower: 1337
                })
            }),
            _toERC721Array(tokenToBuy),
            _toUint256Array(tokenId)
        );
        Party party_ = pb.finalize(defaultGovernanceOpts);
        assertEq(address(party), address(party_));
        // Burn contributor's NFT, mock minting governance tokens and returning
        // unused contribution.
        vm.expectEmit(false, false, false, true);
        emit MockPartyFactoryMint(
            address(pb),
            party_,
            contributor,
            1337,
            delegate
        );
        pb.burn(contributor);
        assertEq(contributor.balance, 1e18 - 1337);
    }
}
