// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/proposals/opensea/LibWyvernExchangeV2.sol";

import "../TestUtils.sol";
import "../DummyERC721.sol";
import "./TestableListOnOpenSeaProposal.sol";
import "./ZoraTestUtils.sol";
import "./OpenSeaTestUtils.sol";

contract ListOnOpenSeaProposalTest is
    Test,
    TestUtils,
    ZoraTestUtils,
    OpenSeaTestUtils
{
    address constant BUYER = 0xf40d7A893a7Fe7d9dae086c662f4233Ae3Df9EC4;
    uint256 constant ZORA_LISTING_DURATION = 60 * 60 * 24;
    uint256 constant LIST_PRICE = 1e18;
    TestableListOnOpenSeaProposal impl;
    Globals globals;
    SharedWyvernV2Maker sharedMaker;
    IWyvernExchangeV2 OS =
        IWyvernExchangeV2(0x7f268357A8c2552623316e2562D90e642bB538E5);
    IZoraAuctionHouse ZORA =
        IZoraAuctionHouse(0xE468cE99444174Bd3bBBEd09209577d25D1ad673);
    DummyERC721[] preciousTokens;
    uint256[] preciousTokenIds;

    constructor() ZoraTestUtils(ZORA) OpenSeaTestUtils(OS) {}

    function setUp() public onlyForked {
        globals = new Globals(address(this));
        globals.setUint256(
            LibGlobals.GLOBAL_OS_ZORA_AUCTION_DURATION,
            ZORA_LISTING_DURATION
        );
        preciousTokens.push(new DummyERC721());
        preciousTokens.push(new DummyERC721());
        preciousTokenIds.push(preciousTokens[0].mint(address(this)));
        preciousTokenIds.push(preciousTokens[1].mint(address(this)));
        sharedMaker = new SharedWyvernV2Maker(OS);
        impl = new TestableListOnOpenSeaProposal(
            globals,
            sharedMaker,
            ZORA
        );
        for (uint256 i = 0; i < preciousTokens.length; ++i) {
            preciousTokens[i].transferFrom(address(this), address(impl), preciousTokenIds[i]);
        }
    }

    function _createTestProposal(IERC721 token, uint256 tokenId)
        private
        view
        returns (
            ListOnOpenSeaProposal.OpenSeaProposalData memory proposalData,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        )
    {
        proposalData =
            ListOnOpenSeaProposal.OpenSeaProposalData({
                listPrice: LIST_PRICE,
                duration: uint40(ZORA_LISTING_DURATION * 7),
                token: token,
                tokenId: tokenId
            });
        IERC721[] memory preciousTokens_ = new IERC721[](preciousTokens.length);
        for (uint256 i = 0; i < preciousTokens_.length; ++i) {
            preciousTokens_[i] = IERC721(preciousTokens[i]);
        }
        executeParams =
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomBytes32(),
                proposalData: abi.encode(proposalData),
                progressData: "",
                flags: 0,
                preciousTokens: preciousTokens_,
                preciousTokenIds: preciousTokenIds
            });
    }

    function _randomPreciousToken()
        private
        view
        returns (IERC721 token, uint256 tokenId)
    {
        uint256 idx = _randomRange(0, preciousTokens.length);
        return (preciousTokens[idx], preciousTokenIds[idx]);
    }

    // Test complete proposal execution steps, with all listings
    // expiring.
    function testForked_Execution_AllExpiring() public onlyForked {
        (IERC721 token, uint256 tokenId) = _randomPreciousToken();
        (
            ListOnOpenSeaProposal.OpenSeaProposalData memory proposalData,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        ) = _createTestProposal(token, tokenId);
        // This will list on zora because the proposal was not passed unanimously.
        executeParams.progressData = impl.executeListOnOpenSea(executeParams);
        assertTrue(executeParams.progressData.length != 0);
        {
            (
                ListOnOpenSeaProposal.OpenSeaStep step,
                ZoraHelpers.ZoraProgressData memory progressData
            ) = abi.decode(executeParams.progressData, (
                ListOnOpenSeaProposal.OpenSeaStep,
                ZoraHelpers.ZoraProgressData
            ));
            assertTrue(step == ListOnOpenSeaProposal.OpenSeaStep.ListedOnZora);
            assertTrue(progressData.auctionId != 0);
            assertTrue(progressData.minExpiry == block.timestamp + ZORA_LISTING_DURATION);
        }
        // Precious should be held by zora.
        assertTrue(token.ownerOf(tokenId) == address(ZORA));
        // Expire the zora listing.
        skip(ZORA_LISTING_DURATION);
        // Next, retrieve from zora and list on OS.
        executeParams.progressData = impl.executeListOnOpenSea(executeParams);
        assertTrue(executeParams.progressData.length != 0);
        {
            (
                ListOnOpenSeaProposal.OpenSeaStep step,
                bytes32 orderHash,
                uint256 expiry
            ) = abi.decode(executeParams.progressData, (
                ListOnOpenSeaProposal.OpenSeaStep,
                bytes32,
                uint256
            ));
            assertTrue(step == ListOnOpenSeaProposal.OpenSeaStep.ListedOnOpenSea);
            assertTrue(orderHash != bytes32(0));
            assertTrue(expiry == block.timestamp + proposalData.duration);
            // Order should be approved on the exchange.
            assertTrue(OS.approvedOrders(orderHash));
        }
        // Precious should be held by the shared wyvern sharedMaker.
        assertTrue(token.ownerOf(tokenId) == address(sharedMaker));
        // Expire the OS listing.
        skip(proposalData.duration);
        executeParams.progressData = impl.executeListOnOpenSea(executeParams);
        assertTrue(executeParams.progressData.length == 0);
        // Precious should be held by the proposal contract.
        assertTrue(token.ownerOf(tokenId) == address(impl));
        // Done
    }

    // Test complete proposal execution steps, with unanimous votes, all listings
    // expiring.
    function testForked_Execution_UnanimousVote_AllExpiring() public onlyForked {
        (IERC721 token, uint256 tokenId) = _randomPreciousToken();
        (
            ListOnOpenSeaProposal.OpenSeaProposalData memory proposalData,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        ) = _createTestProposal(token, tokenId);
        executeParams.flags |= LibProposal.PROPOSAL_FLAG_UNANIMOUS;
        // This will list straight on OS because it was a unanmous vote.
        executeParams.progressData = impl.executeListOnOpenSea(executeParams);
        assertTrue(executeParams.progressData.length != 0);
        {
            (
                ListOnOpenSeaProposal.OpenSeaStep step,
                bytes32 orderHash,
                uint256 expiry
            ) = abi.decode(executeParams.progressData, (
                ListOnOpenSeaProposal.OpenSeaStep,
                bytes32,
                uint256
            ));
            assertTrue(step == ListOnOpenSeaProposal.OpenSeaStep.ListedOnOpenSea);
            assertTrue(orderHash != bytes32(0));
            assertTrue(expiry == block.timestamp + proposalData.duration);
            // Order should be approved on the exchange.
            assertTrue(OS.approvedOrders(orderHash));
        }
        // Precious should be held by the shared wyvern sharedMaker.
        assertTrue(token.ownerOf(tokenId) == address(sharedMaker));
        // Expire the OS listing.
        skip(proposalData.duration);
        executeParams.progressData = impl.executeListOnOpenSea(executeParams);
        assertTrue(executeParams.progressData.length == 0);
        // Done
    }

    // Zora listing was bid on but not finalized.
    function testForked_Execution_ZoraBidUp() public onlyForked {
        (IERC721 token, uint256 tokenId) = _randomPreciousToken();
        (
            ListOnOpenSeaProposal.OpenSeaProposalData memory proposalData,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        ) = _createTestProposal(token, tokenId);
        // This will list on zora because the proposal was not passed unanimously.
        executeParams.progressData = impl.executeListOnOpenSea(executeParams);
        uint256 auctionId;
        {
            (, ZoraHelpers.ZoraProgressData memory progressData) =
                abi.decode(executeParams.progressData, (
                    ListOnOpenSeaProposal.OpenSeaStep,
                    ZoraHelpers.ZoraProgressData
                ));
            auctionId = progressData.auctionId;
        }
        _bidOnZoraListing(auctionId, BUYER, LIST_PRICE);
        // Skip to the end of the auction.
        skip(ZORA_LISTING_DURATION);
        // Finalize the auction.
        executeParams.progressData = impl.executeListOnOpenSea(executeParams);
        assertTrue(executeParams.progressData.length == 0);
        // Buyer should own precious.
        assertTrue(token.ownerOf(tokenId) == BUYER);
        // Proposal contract should have the bid amount.
        assertTrue(address(impl).balance == LIST_PRICE);
    }

    // TODO: test zora listing being bid and finalized by someone else.

    // OS listing was bought.
    function testForked_Execution_OSBought() public onlyForked {
        (IERC721 token, uint256 tokenId) = _randomPreciousToken();
        (
            ListOnOpenSeaProposal.OpenSeaProposalData memory proposalData,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        ) = _createTestProposal(token, tokenId);
        // This will list on zora because the proposal was not passed unanimously.
        executeParams.progressData = impl.executeListOnOpenSea(executeParams);
        // Expire the zora listing.
        skip(ZORA_LISTING_DURATION);
        // Next, retrieve from zora and list on OS.
        executeParams.progressData = impl.executeListOnOpenSea(executeParams);
        bytes32 orderHash;
        uint256 expiry;
        {
            (, orderHash, expiry) = abi.decode(executeParams.progressData, (
                ListOnOpenSeaProposal.OpenSeaStep,
                bytes32,
                uint256
            ));
        }
        // Buy the OS listing.
        IWyvernExchangeV2.Order memory order = LibWyvernExchangeV2.createSellOrder(
            OS,
            address(sharedMaker),
            token,
            tokenId,
            LIST_PRICE,
            expiry
        );
        skip(1); // Cannot fill an order at listing time.
        assertEq(LibWyvernExchangeV2.hashOrder(order), orderHash);
        _buyOpenSeaListing(order, BUYER, token, tokenId);
        // Finalize the listing.
        executeParams.progressData = impl.executeListOnOpenSea(executeParams);
        assertTrue(executeParams.progressData.length == 0);
        // Buyer should own precious.
        assertTrue(token.ownerOf(tokenId) == BUYER);
        // Proposal contract should have the listing amount.
        assertTrue(address(impl).balance == LIST_PRICE);
    }

    // TODO: test failing conditions (e.g., executing next step before expirations, etc.)
    // TODO: test non-precious tokens.
}
