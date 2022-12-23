// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/AuctionCrowdfund.sol";
import "../../contracts/crowdfund/BuyCrowdfund.sol";
import "../../contracts/crowdfund/CollectionBuyCrowdfund.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/utils/PartyHelpers.sol";
import "../../contracts/utils/Proxy.sol";

import "../crowdfund/MockMarketWrapper.sol";
import "../crowdfund/TestERC721Vault.sol";
import "../DummyERC721.sol";
import "../TestUtils.sol";

contract CrowdfundHelpers is Test, TestUtils {
    string defaultName = "AuctionCrowdfund";
    string defaultSymbol = "PBID";
    uint40 defaultDuration = 60 * 60;
    uint96 defaultMaxBid = 10e18;
    uint96 defaultMaxPrice = 10e18;
    address payable defaultSplitRecipient = payable(0);
    uint16 defaultSplitBps = 0.1e4;
    address defaultInitialDelegate;
    IGateKeeper defaultGateKeeper;
    bytes12 defaultGateKeeperId;
    Crowdfund.FixedGovernanceOpts defaultGovernanceOpts;

    Globals globals;
    AuctionCrowdfund auctionCrowdfundImpl;
    BuyCrowdfund buyCrowdfundImpl;
    CollectionBuyCrowdfund collectionBuyCrowdfundImpl;
    MockMarketWrapper market = new MockMarketWrapper();
    TestERC721Vault erc721Vault = new TestERC721Vault();

    constructor() {
        // create globals
        globals = new Globals(address(this));

        // set partybid crowdfund implementation on globals
        auctionCrowdfundImpl = new AuctionCrowdfund(globals);
        globals.setAddress(LibGlobals.GLOBAL_AUCTION_CF_IMPL, address(auctionCrowdfundImpl));

        // set partybuy crowdfund implementation on globals
        buyCrowdfundImpl = new BuyCrowdfund(globals);
        globals.setAddress(LibGlobals.GLOBAL_BUY_CF_IMPL, address(buyCrowdfundImpl));

        // set partycollectionbuy crowdfund implementation on globals
        collectionBuyCrowdfundImpl = new CollectionBuyCrowdfund(globals);
        globals.setAddress(
            LibGlobals.GLOBAL_COLLECTION_BUY_CF_IMPL,
            address(collectionBuyCrowdfundImpl)
        );
    }

    function _createAuctionCrowdfundCrowdfund(
        uint256 auctionId,
        uint256 tokenId,
        uint96 initialContribution
    ) private returns (AuctionCrowdfund cf) {
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
                                nftContract: market.nftContract(),
                                nftTokenId: tokenId,
                                duration: defaultDuration,
                                maximumBid: defaultMaxBid,
                                splitRecipient: defaultSplitRecipient,
                                splitBps: defaultSplitBps,
                                initialContributor: address(this),
                                initialDelegate: defaultInitialDelegate,
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

    function _createBuyCrowdfundCrowdfund(
        uint96 initialContribution
    ) private returns (BuyCrowdfund cf) {
        cf = BuyCrowdfund(
            payable(
                address(
                    new Proxy{ value: initialContribution }(
                        buyCrowdfundImpl,
                        abi.encodeCall(
                            BuyCrowdfund.initialize,
                            BuyCrowdfund.BuyCrowdfundOptions({
                                name: defaultName,
                                symbol: defaultSymbol,
                                customizationPresetId: 0,
                                nftContract: erc721Vault.token(),
                                nftTokenId: erc721Vault.mint(),
                                duration: defaultDuration,
                                maximumPrice: defaultMaxPrice,
                                splitRecipient: defaultSplitRecipient,
                                splitBps: defaultSplitBps,
                                initialContributor: address(this),
                                initialDelegate: defaultInitialDelegate,
                                minContribution: 0,
                                maxContribution: type(uint96).max,
                                gateKeeper: defaultGateKeeper,
                                gateKeeperId: defaultGateKeeperId,
                                onlyHostCanBuy: false,
                                governanceOpts: defaultGovernanceOpts
                            })
                        )
                    )
                )
            )
        );
    }

    function _createCollectionBuyCrowdfundCrowdfund(
        uint96 initialContribution
    ) private returns (CollectionBuyCrowdfund cf) {
        defaultGovernanceOpts.hosts = _toAddressArray(_randomAddress());
        cf = CollectionBuyCrowdfund(
            payable(
                address(
                    new Proxy{ value: initialContribution }(
                        collectionBuyCrowdfundImpl,
                        abi.encodeCall(
                            CollectionBuyCrowdfund.initialize,
                            CollectionBuyCrowdfund.CollectionBuyCrowdfundOptions({
                                name: defaultName,
                                symbol: defaultSymbol,
                                customizationPresetId: 0,
                                nftContract: erc721Vault.token(),
                                duration: defaultDuration,
                                maximumPrice: defaultMaxPrice,
                                splitRecipient: defaultSplitRecipient,
                                splitBps: defaultSplitBps,
                                initialContributor: address(this),
                                initialDelegate: defaultInitialDelegate,
                                minContribution: 0,
                                maxContribution: type(uint96).max,
                                gateKeeper: defaultGateKeeper,
                                gateKeeperId: defaultGateKeeperId,
                                governanceOpts: defaultGovernanceOpts
                            })
                        )
                    )
                )
            )
        );
    }

    function testGetAuctionCrowdfundCrowdfundType() public {
        (uint256 auctionId, uint256 tokenId) = market.createAuction(1337);

        // create partybid crowdfund
        AuctionCrowdfund pbid = _createAuctionCrowdfundCrowdfund(auctionId, tokenId, 0);

        // create party helpers
        PartyHelpers ph = new PartyHelpers();

        PartyHelpers.CrowdfundType cft = ph.getCrowdfundType(address(globals), address(pbid));
        assertEq(uint256(cft), 0);
    }

    function testGetBuyCrowdfundCrowdfundType() public {
        // create partybuy crowdfund
        BuyCrowdfund pbuy = _createBuyCrowdfundCrowdfund(0);

        // create party helpers
        PartyHelpers ph = new PartyHelpers();

        PartyHelpers.CrowdfundType cft = ph.getCrowdfundType(address(globals), address(pbuy));
        assertEq(uint256(cft), 1);
    }

    function testGetCollectionBuyCrowdfundCrowdfundType() public {
        // create partycollectionbuy crowdfund
        CollectionBuyCrowdfund pcb = _createCollectionBuyCrowdfundCrowdfund(0);

        // create party helpers
        PartyHelpers ph = new PartyHelpers();

        PartyHelpers.CrowdfundType cft = ph.getCrowdfundType(address(globals), address(pcb));
        assertEq(uint256(cft), 2);
    }
}
