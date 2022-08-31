// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/PartyBid.sol";
import "../../contracts/crowdfund/PartyBuy.sol";
import "../../contracts/crowdfund/PartyCollectionBuy.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/utils/PartyHelpers.sol";
import "../../contracts/utils/Proxy.sol";

import "../crowdfund/MockMarketWrapper.sol";
import "../crowdfund/TestERC721Vault.sol";
import "../DummyERC721.sol";
import "../TestUtils.sol";

contract PartyCrowdfundHelpers is Test, TestUtils {
    string defaultName = 'PartyBid';
    string defaultSymbol = 'PBID';
    uint40 defaultDuration = 60 * 60;
    uint96 defaultMaxBid = 10e18;
    uint96 defaultMaxPrice = 10e18;
    address payable defaultSplitRecipient = payable(0);
    uint16 defaultSplitBps = 0.1e4;
    address defaultInitialDelegate;
    IGateKeeper defaultGateKeeper;
    bytes12 defaultGateKeeperId;
    PartyCrowdfund.FixedGovernanceOpts defaultGovernanceOpts;

    Globals globals;
    PartyBid partyBidImpl;
    PartyBuy partyBuyImpl;
    PartyCollectionBuy partyCollectionBuyImpl;
    MockMarketWrapper market = new MockMarketWrapper();
    TestERC721Vault erc721Vault = new TestERC721Vault();

    constructor() {
      // create globals
      globals = new Globals(address(this));

      // set partybid crowdfund implementation on globals
      partyBidImpl = new PartyBid(globals);
      globals.setAddress(LibGlobals.GLOBAL_PARTY_BID_IMPL, address(partyBidImpl));

      // set partybuy crowdfund implementation on globals
      partyBuyImpl = new PartyBuy(globals);
      globals.setAddress(LibGlobals.GLOBAL_PARTY_BUY_IMPL, address(partyBuyImpl));

      // set partycollectionbuy crowdfund implementation on globals
      partyCollectionBuyImpl = new PartyCollectionBuy(globals);
      globals.setAddress(LibGlobals.GLOBAL_PARTY_COLLECTION_BUY_IMPL, address(partyCollectionBuyImpl));
    }

    function _createPartyBidCrowdfund(
        uint256 auctionId,
        uint256 tokenId,
        uint96 initialContribution
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
                    nftContract: market.nftContract(),
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

    function _createPartyBuyCrowdfund(uint96 initialContribution)
        private
        returns (PartyBuy pb)
    {
        pb = PartyBuy(payable(address(new Proxy{ value: initialContribution }(
            partyBuyImpl,
            abi.encodeCall(
                PartyBuy.initialize,
                PartyBuy.PartyBuyOptions({
                    name: defaultName,
                    symbol: defaultSymbol,
                    nftContract: erc721Vault.token(),
                    nftTokenId: erc721Vault.mint(),
                    duration: defaultDuration,
                    maximumPrice: defaultMaxPrice,
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

    function _createPartyCollectionBuyCrowdfund(uint96 initialContribution)
        private
        returns (PartyCollectionBuy pb)
    {
        pb = PartyCollectionBuy(payable(address(new Proxy{ value: initialContribution }(
            partyCollectionBuyImpl,
            abi.encodeCall(
                PartyCollectionBuy.initialize,
                PartyCollectionBuy.PartyCollectionBuyOptions({
                    name: defaultName,
                    symbol: defaultSymbol,
                    nftContract: erc721Vault.token(),
                    duration: defaultDuration,
                    maximumPrice: defaultMaxPrice,
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

    function testGetPartyBidCrowdfundType() public {
      (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);

      // create partybid crowdfund
      PartyBid pbid = _createPartyBidCrowdfund(auctionId, tokenId, 0);

      // create party helpers
      PartyHelpers ph = new PartyHelpers();

      PartyHelpers.CrowdfundType cft = ph.getCrowdfundType(address(globals), address(pbid));
      assertEq(uint256(cft), 0);
    }

    function testGetPartyBuyCrowdfundType() public {
      // create partybuy crowdfund
      PartyBuy pbuy = _createPartyBuyCrowdfund(0);

      // create party helpers
      PartyHelpers ph = new PartyHelpers();

      PartyHelpers.CrowdfundType cft = ph.getCrowdfundType(address(globals), address(pbuy));
      assertEq(uint256(cft), 1);
    }

    function testGetPartyCollectionBuyCrowdfundType() public {
      // create partycollectionbuy crowdfund
      PartyCollectionBuy pcb = _createPartyCollectionBuyCrowdfund(0);

      // create party helpers
      PartyHelpers ph = new PartyHelpers();

      PartyHelpers.CrowdfundType cft = ph.getCrowdfundType(address(globals), address(pcb));
      assertEq(uint256(cft), 2);
    }
}
