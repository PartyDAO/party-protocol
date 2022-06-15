// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/proposals/opensea/ISeaportExchange.sol";

import "../TestUtils.sol";
import "../DummyERC721.sol";
import "./TestableListOnOpenSeaportProposal.sol";
import "./ZoraTestUtils.sol";
import "./OpenSeaportTestUtils.sol";

contract ListOnOpenSeaportProposalTest is
    Test,
    TestUtils,
    ZoraTestUtils,
    OpenSeaportTestUtils
{
    uint256 constant ZORA_LISTING_DURATION = 1 days;
    uint256 constant LIST_PRICE = 1e18;
    TestableListOnOpenSeaportProposal impl;
    Globals globals;
    ISeaportExchange SEAPORT =
        ISeaportExchange(0x00000000006CEE72100D161c57ADA5Bb2be1CA79);
    IZoraAuctionHouse ZORA =
        IZoraAuctionHouse(0xE468cE99444174Bd3bBBEd09209577d25D1ad673);
    IERC721[] preciousTokens;
    uint256[] preciousTokenIds;

    constructor() ZoraTestUtils(ZORA) OpenSeaportTestUtils(SEAPORT) {}

    function setUp() public onlyForked {
        globals = new Globals(address(this));
        globals.setUint256(
            LibGlobals.GLOBAL_OS_ZORA_AUCTION_DURATION,
            ZORA_LISTING_DURATION
        );
        impl = new TestableListOnOpenSeaportProposal(
            globals,
            SEAPORT,
            ZORA
        );
        (preciousTokens, preciousTokenIds) = _createPreciousTokens(address(impl), 2);
    }

    function _createPreciousTokens(address owner, uint256 count)
        private
        returns (IERC721[] memory tokens, uint256[] memory tokenIds)
    {
        tokens = new IERC721[](count);
        tokenIds = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            DummyERC721 t = new DummyERC721();
            tokens[i] = t;
            tokenIds[i] = t.mint(owner);
        }
    }

    function _createTestProposal(IERC721 token, uint256 tokenId, uint256 listPrice, uint40 duration)
        private
        view
        returns (
            ListOnOpenSeaportProposal.OpenSeaportProposalData memory proposalData,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        )
    {
        proposalData =
            ListOnOpenSeaportProposal.OpenSeaportProposalData({
                listPrice: listPrice,
                duration: duration,
                token: token,
                tokenId: tokenId
            });
        executeParams =
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomBytes32(),
                proposalData: abi.encode(proposalData),
                progressData: "",
                flags: 0,
                preciousTokens: preciousTokens,
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

    // // Test complete proposal execution steps, with all listings
    // // expiring.
    // function testForked_Execution_AllExpiring() public onlyForked {
    //     (IERC721 token, uint256 tokenId) = _randomPreciousToken();
    //     (
    //         ListOnOpenSeaportProposal.OpenSeaportProposalData memory proposalData,
    //         IProposalExecutionEngine.ExecuteProposalParams memory executeParams
    //     ) = _createTestProposal(token, tokenId);
    //     // This will list on zora because the proposal was not passed unanimously.
    //     executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
    //     assertTrue(executeParams.progressData.length != 0);
    //     {
    //         (
    //             ListOnOpenSeaportProposal.OpenSeaStep step,
    //             ZoraHelpers.ZoraProgressData memory progressData
    //         ) = abi.decode(executeParams.progressData, (
    //             ListOnOpenSeaportProposal.OpenSeaStep,
    //             ZoraHelpers.ZoraProgressData
    //         ));
    //         assertTrue(step == ListOnOpenSeaportProposal.OpenSeaStep.ListedOnZora);
    //         assertTrue(progressData.auctionId != 0);
    //         assertTrue(progressData.minExpiry == block.timestamp + ZORA_LISTING_DURATION);
    //     }
    //     // Precious should be held by zora.
    //     assertTrue(token.ownerOf(tokenId) == address(ZORA));
    //     // Expire the zora listing.
    //     skip(ZORA_LISTING_DURATION);
    //     // Next, retrieve from zora and list on OS.
    //     executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
    //     assertTrue(executeParams.progressData.length != 0);
    //     {
    //         (
    //             ListOnOpenSeaportProposal.OpenSeaStep step,
    //             bytes32 orderHash,
    //             uint256 expiry
    //         ) = abi.decode(executeParams.progressData, (
    //             ListOnOpenSeaportProposal.OpenSeaStep,
    //             bytes32,
    //             uint256
    //         ));
    //         assertTrue(step == ListOnOpenSeaportProposal.OpenSeaStep.ListedOnOpenSea);
    //         assertTrue(orderHash != bytes32(0));
    //         assertTrue(expiry == block.timestamp + proposalData.duration);
    //         // Order should be approved on the exchange.
    //         assertTrue(OS.approvedOrders(orderHash));
    //     }
    //     // Precious should be held by the shared wyvern sharedMaker.
    //     assertTrue(token.ownerOf(tokenId) == address(sharedMaker));
    //     // Expire the OS listing.
    //     skip(proposalData.duration);
    //     executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
    //     assertTrue(executeParams.progressData.length == 0);
    //     // Precious should be held by the proposal contract.
    //     assertTrue(token.ownerOf(tokenId) == address(impl));
    //     // Done
    // }
    //
    // // Test complete proposal execution steps, with unanimous votes, all listings
    // // expiring.
    // function testForked_Execution_UnanimousVote_AllExpiring() public onlyForked {
    //     (IERC721 token, uint256 tokenId) = _randomPreciousToken();
    //     (
    //         ListOnOpenSeaportProposal.OpenSeaportProposalData memory proposalData,
    //         IProposalExecutionEngine.ExecuteProposalParams memory executeParams
    //     ) = _createTestProposal(token, tokenId);
    //     executeParams.flags |= LibProposal.PROPOSAL_FLAG_UNANIMOUS;
    //     // This will list straight on OS because it was a unanmous vote.
    //     executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
    //     assertTrue(executeParams.progressData.length != 0);
    //     {
    //         (
    //             ListOnOpenSeaportProposal.OpenSeaStep step,
    //             bytes32 orderHash,
    //             uint256 expiry
    //         ) = abi.decode(executeParams.progressData, (
    //             ListOnOpenSeaportProposal.OpenSeaStep,
    //             bytes32,
    //             uint256
    //         ));
    //         assertTrue(step == ListOnOpenSeaportProposal.OpenSeaStep.ListedOnOpenSea);
    //         assertTrue(orderHash != bytes32(0));
    //         assertTrue(expiry == block.timestamp + proposalData.duration);
    //         // Order should be approved on the exchange.
    //         assertTrue(OS.approvedOrders(orderHash));
    //     }
    //     // Precious should be held by the shared wyvern sharedMaker.
    //     assertTrue(token.ownerOf(tokenId) == address(sharedMaker));
    //     // Expire the OS listing.
    //     skip(proposalData.duration);
    //     executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
    //     assertTrue(executeParams.progressData.length == 0);
    //     // Done
    // }
    //
    // // Zora listing was bid on but not finalized.
    // function testForked_Execution_ZoraBidUp() public onlyForked {
    //     (IERC721 token, uint256 tokenId) = _randomPreciousToken();
    //     (
    //         ListOnOpenSeaportProposal.OpenSeaportProposalData memory proposalData,
    //         IProposalExecutionEngine.ExecuteProposalParams memory executeParams
    //     ) = _createTestProposal(token, tokenId);
    //     // This will list on zora because the proposal was not passed unanimously.
    //     executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
    //     uint256 auctionId;
    //     {
    //         (, ZoraHelpers.ZoraProgressData memory progressData) =
    //             abi.decode(executeParams.progressData, (
    //                 ListOnOpenSeaportProposal.OpenSeaStep,
    //                 ZoraHelpers.ZoraProgressData
    //             ));
    //         auctionId = progressData.auctionId;
    //     }
    //     _bidOnZoraListing(auctionId, BUYER, LIST_PRICE);
    //     // Skip to the end of the auction.
    //     skip(ZORA_LISTING_DURATION);
    //     // Finalize the auction.
    //     executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
    //     assertTrue(executeParams.progressData.length == 0);
    //     // Buyer should own precious.
    //     assertTrue(token.ownerOf(tokenId) == BUYER);
    //     // Proposal contract should have the bid amount.
    //     assertTrue(address(impl).balance == LIST_PRICE);
    // }

    // TODO: test zora listing being bid and finalized by someone else.

    // OS listing was bought.
    function testForked_Execution_OSBought() public onlyForked {
        address buyer = _randomAddress();
        uint256 listPrice = 1e18;
        uint40 listDuration = 7 days;
        (IERC721 token, uint256 tokenId) = _randomPreciousToken();
        (
            ,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        ) = _createTestProposal(token, tokenId, listPrice, listDuration);
        // This will list on zora because the proposal was not passed unanimously.
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        // Expire the zora listing.
        skip(ZORA_LISTING_DURATION);
        // Next, retrieve from zora and list on OS.
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        bytes32 orderHash;
        uint256 expiry;
        {
            (, orderHash, expiry) = abi.decode(executeParams.progressData, (
                ListOnOpenSeaportProposal.OpenSeaportStep,
                bytes32,
                uint256
            ));
        }
        // Buy the OS listing.
        uint256 listStartTime = block.timestamp;

        _buyOpenSeaportListing(payable(impl), buyer, token, tokenId, listPrice, listStartTime, listDuration);
        // Finalize the listing.
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        assertTrue(executeParams.progressData.length == 0);
        // Buyer should own precious.
        assertTrue(token.ownerOf(tokenId) == buyer);
        // Proposal contract should have the list price.
        assertTrue(address(impl).balance == LIST_PRICE);
    }

    // TODO: test failing conditions (e.g., executing next step before expirations, etc.)
    // TODO: test non-precious tokens.
}
