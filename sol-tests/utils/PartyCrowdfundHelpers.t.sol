// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/console2.sol";
import "forge-std/Test.sol";

import "../../contracts/crowdfund/PartyBid.sol";
import "../../contracts/crowdfund/PartyBuy.sol";
import "../../contracts/crowdfund/PartyCollectionBuy.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/utils/PartyHelpers.sol";
import "../../contracts/utils/Proxy.sol";

import "../DummyERC721.sol";
import "../TestUtils.sol";

import "../crowdfund/MockPartyFactory.sol";
import "../crowdfund/TestERC721Vault.sol";
import "../crowdfund/MockMarketWrapper.sol";

contract PartyCrowdfundHelpers is Test, TestUtils {
    string defaultName = 'PartyBid';
    string defaultSymbol = 'PBID';
    uint40 defaultDuration = 60 * 60;
    uint128 defaultMaxBid = 10e18;
    uint128 defaultMaxPrice = 10e18;
    address payable defaultSplitRecipient = payable(0);
    uint16 defaultSplitBps = 0.1e4;
    address defaultInitialDelegate;
    IGateKeeper defaultGateKeeper;
    bytes12 defaultGateKeeperId;
    PartyCrowdfund.FixedGovernanceOpts defaultGovernanceOpts;

    Globals globals;
    PartyBid partyBidImpl;
    PartyBuy partyBuyImpl;
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
    }

    function _createPartyBidCrowdfund(
        uint256 auctionId,
        IERC721 tokenContract,
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
                    nftContract: tokenContract,
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

    function _createPartyBuyCrowdfund(
        IERC721 tokenContract,
        uint256 tokenId,
        uint128 initialContribution
    )
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
                    nftContract: tokenContract,
                    nftTokenId: tokenId,
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

    // function _createPartyCollectionBuyCrowdfund(
    //   PartyCollectionBuy partyCollectionBuyImpl,
    //   uint128 initialContribution
    // )
    //     private
    //     returns (PartyCollectionBuy pb)
    // {
    //     pb = PartyCollectionBuy(payable(address(new Proxy{ value: initialContribution }(
    //         partyCollectionBuyImpl,
    //         abi.encodeCall(
    //             PartyCollectionBuy.initialize,
    //             PartyCollectionBuy.PartyCollectionBuyOptions({
    //                 name: defaultName,
    //                 symbol: defaultSymbol,
    //                 nftContract: erc721Vault.token(),
    //                 duration: defaultDuration,
    //                 maximumPrice: defaultMaxPrice,
    //                 splitRecipient: defaultSplitRecipient,
    //                 splitBps: defaultSplitBps,
    //                 initialContributor: address(this),
    //                 initialDelegate: defaultInitialDelegate,
    //                 gateKeeper: defaultGateKeeper,
    //                 gateKeeperId: defaultGateKeeperId,
    //                 governanceOpts: defaultGovernanceOpts
    //             })
    //         )
    //     ))));
    // }

    function testGetPartyBidCrowdfundType() public {
      DummyERC721 tokenToBuy = market.nftContract();
      (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);

      // create partybid crowdfund
      PartyBid pb = _createPartyBidCrowdfund(auctionId, tokenToBuy, tokenId, 0);

      // create party helpers
      PartyHelpers ph = new PartyHelpers();

      PartyHelpers.CrowdfundType cft = ph.getCrowdfundType(address(globals), address(pb));
      console2.log('partybid cft', uint256(cft));
      assertEq(uint256(cft), 0);
    }

    function testGetPartyBuyCrowdfundType() public {
      uint256 tokenId = erc721Vault.mint();

      // create partybuy crowdfund
      PartyBuy pb = _createPartyBuyCrowdfund(erc721Vault.token(), tokenId, 0);

      // create party helpers
      PartyHelpers ph = new PartyHelpers();

      PartyHelpers.CrowdfundType cft = ph.getCrowdfundType(address(globals), address(pb));
      assertEq(uint256(cft), 1);
    }
}
