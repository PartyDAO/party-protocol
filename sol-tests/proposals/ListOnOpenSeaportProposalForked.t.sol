// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/proposals/vendor/ISeaportExchange.sol";

import "../TestUtils.sol";
import "../DummyERC721.sol";
import "./TestableListOnOpenSeaportProposal.sol";
import "./ZoraTestUtils.sol";
import "./OpenSeaportTestUtils.sol";

contract ListOnOpenSeaportProposalForkedTest is
    Test,
    TestUtils,
    ZoraTestUtils,
    OpenSeaportTestUtils
{
    event OpenSeaportOrderListed(
        ISeaportExchange.OrderParameters orderParams,
        bytes32 orderHash,
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice,
        uint256 expiry
    );
    event OpenSeaportOrderSold(
        bytes32 orderHash,
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice
    );
    event OpenSeaportOrderExpired(
        bytes32 orderHash,
        IERC721 token,
        uint256 tokenId,
        uint256 expiry
    );
    event ZoraAuctionCreated(
        uint256 auctionId,
        IERC721 token,
        uint256 tokenId,
        uint256 startingPrice,
        uint40 expiry,
        uint40 timeoutTime
    );
    event ZoraAuctionExpired(uint256 auctionId, uint256 expiry);
    event ZoraAuctionSold(uint256 auctionId);

    uint256 constant ZORA_AUCTION_DURATION = 0.5 days;
    uint256 constant ZORA_AUCTION_TIMEOUT = 1 days;
    uint256 constant LIST_PRICE = 1e18;
    TestableListOnOpenSeaportProposal impl;
    Globals globals;
    ISeaportExchange SEAPORT =
        ISeaportExchange(0x00000000006c3852cbEf3e08E8dF289169EdE581);
    ISeaportConduitController CONDUIT_CONTROLLER =
        ISeaportConduitController(0x00000000F9490004C11Cef243f5400493c00Ad63);
    IZoraAuctionHouse ZORA =
        IZoraAuctionHouse(0xE468cE99444174Bd3bBBEd09209577d25D1ad673);
    address SEAPORT_ZONE = 0x004C00500000aD104D7DBd00e3ae0A5C00560C00;
    bytes32 SEAPORT_CONDUIT_KEY = 0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000;
    IERC721[] preciousTokens;
    uint256[] preciousTokenIds;

    constructor() ZoraTestUtils(ZORA) OpenSeaportTestUtils(SEAPORT) {}

    function setUp() public onlyForked {
        globals = new Globals(address(this));
        globals.setBytes32(
            LibGlobals.GLOBAL_OPENSEA_CONDUIT_KEY,
            SEAPORT_CONDUIT_KEY
        );
        globals.setAddress(
            LibGlobals.GLOBAL_OPENSEA_ZONE,
            SEAPORT_ZONE
        );
        globals.setUint256(
            LibGlobals.GLOBAL_OS_ZORA_AUCTION_TIMEOUT,
            ZORA_AUCTION_TIMEOUT
        );
        globals.setUint256(
            LibGlobals.GLOBAL_OS_ZORA_AUCTION_DURATION,
            ZORA_AUCTION_DURATION
        );
        impl = new TestableListOnOpenSeaportProposal(
            globals,
            SEAPORT,
            CONDUIT_CONTROLLER,
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

    function _createTestProposal(
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice,
        uint40 duration,
        uint256[] memory fees,
        address payable[] memory feeRecipients
    )
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
                tokenId: tokenId,
                fees: fees,
                feeRecipients: feeRecipients
            });
        executeParams =
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                proposalData: abi.encode(proposalData),
                progressData: "",
                extraData: "",
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

    // Test a proposal where the zora listing times out and the
    // OS listing gets bought.
    function testForked_Execution_OSBought() public onlyForked {
        address buyer = _randomAddress();
        uint256 listPrice = 1e18;
        uint40 listDuration = 7 days;
        (IERC721 token, uint256 tokenId) = _randomPreciousToken();
        (
            ,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        ) = _createTestProposal(
            token,
            tokenId,
            listPrice,
            listDuration,
            new uint256[](0),
            new address payable[](0)
        );
        // This will list on zora because the proposal was not passed unanimously.
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        // Time out the zora listing.
        skip(ZORA_AUCTION_TIMEOUT);
        // Next, retrieve from zora and list on OS.
        uint256 listStartTime = block.timestamp;
        // TODO: check OpenSeaportOrderListed event gets emitted.
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        bytes32 orderHash;
        {
            (, orderHash,) = abi.decode(executeParams.progressData, (
                ListOnOpenSeaportProposal.ListOnOpenSeaportStep,
                bytes32,
                uint256
            ));
        }
        // Buy the OS listing.
        _buyOpenSeaportListing(BuyOpenSeaportListingParams({
            maker: payable(impl),
            buyer: buyer,
            token: token,
            tokenId: tokenId,
            listPrice: listPrice,
            startTime: listStartTime,
            duration: listDuration,
            zone: SEAPORT_ZONE,
            conduitKey: SEAPORT_CONDUIT_KEY
        }));
        // Finalize the listing.
        vm.expectEmit(false, false, false, true);
        emit OpenSeaportOrderSold(orderHash, token, tokenId, listPrice);
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        assertEq(executeParams.progressData.length, 0);
        // Buyer should own the NFT.
        assertEq(token.ownerOf(tokenId), buyer);
        // Proposal contract should have the list price.
        assertEq(address(impl).balance, LIST_PRICE);
    }

    // Test a proposal where the zora listing times out and the
    // OS listing gets bought, with fees.
    function testForked_Execution_OSBoughtWithFees() public onlyForked {
        address buyer = _randomAddress();
        uint256 listPrice = 1e18;
        uint40 listDuration = 7 days;
        uint256[] memory fees = new uint256[](1);
        fees[0] = 0.0123e18;
        address payable[] memory feeRecipients = new address payable[](1);
        feeRecipients[0] = _randomAddress();
        (IERC721 token, uint256 tokenId) = _randomPreciousToken();
        (
            ,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        ) = _createTestProposal(
            token,
            tokenId,
            listPrice,
            listDuration,
            fees,
            feeRecipients
        );
        // This will list on zora because the proposal was not passed unanimously.
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        // Time out the zora listing.
        skip(ZORA_AUCTION_TIMEOUT);
        // Next, retrieve from zora and list on OS.
        uint256 listStartTime = block.timestamp;
        // TODO: check OpenSeaportOrderListed event gets emitted.
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        bytes32 orderHash;
        {
            (, orderHash,) = abi.decode(executeParams.progressData, (
                ListOnOpenSeaportProposal.ListOnOpenSeaportStep,
                bytes32,
                uint256
            ));
        }
        // Buy the OS listing.
        _buyOpenSeaportListing(
            BuyOpenSeaportListingParams({
                maker: payable(impl),
                buyer: buyer,
                token: token,
                tokenId: tokenId,
                listPrice: listPrice,
                startTime: listStartTime,
                duration: listDuration,
                zone: SEAPORT_ZONE,
                conduitKey: SEAPORT_CONDUIT_KEY
            }),
            fees,
            feeRecipients
        );
        // Finalize the listing.
        vm.expectEmit(false, false, false, true);
        emit OpenSeaportOrderSold(orderHash, token, tokenId, listPrice);
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        assertEq(executeParams.progressData.length, 0);
        // Buyer should own the NFT.
        assertEq(token.ownerOf(tokenId), buyer);
        // Proposal contract should have the list price.
        assertEq(address(impl).balance, LIST_PRICE);
    }

    // Test a unanmous proposal where the OS listing gets bought.
    function testForked_Execution_OSBought_Unanimous() public onlyForked {
        address buyer = _randomAddress();
        uint256 listPrice = 1e18;
        uint40 listDuration = 7 days;
        (IERC721 token, uint256 tokenId) = _randomPreciousToken();
        (
            ,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        ) = _createTestProposal(
            token,
            tokenId,
            listPrice,
            listDuration,
            new uint256[](0),
            new address payable[](0)
        );
        executeParams.flags |= LibProposal.PROPOSAL_FLAG_UNANIMOUS;
        // This will skip zora and list directly on OS because the proposal was
        // passed unanimously.
        uint256 listStartTime = block.timestamp;
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        bytes32 orderHash;
        {
            (, orderHash,) = abi.decode(executeParams.progressData, (
                ListOnOpenSeaportProposal.ListOnOpenSeaportStep,
                bytes32,
                uint256
            ));
        }
        // Buy the OS listing.
        _buyOpenSeaportListing(BuyOpenSeaportListingParams({
            maker: payable(impl),
            buyer: buyer,
            token: token,
            tokenId: tokenId,
            listPrice: listPrice,
            startTime: listStartTime,
            duration: listDuration,
            zone: SEAPORT_ZONE,
            conduitKey: SEAPORT_CONDUIT_KEY
        }));
        // Finalize the listing.
        vm.expectEmit(false, false, false, true);
        emit OpenSeaportOrderSold(orderHash, token, tokenId, listPrice);
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        assertEq(executeParams.progressData.length, 0);
        // Buyer should own the NFT.
        assertEq(token.ownerOf(tokenId), buyer);
        // Proposal contract should have the list price.
        assertEq(address(impl).balance, LIST_PRICE);
    }

    // Test a proposal for a non-precious token where the OS listing gets bought.
    function testForked_Execution_OSBought_NonPreciousToken() public onlyForked {
        address buyer = _randomAddress();
        uint256 listPrice = 1e18;
        uint40 listDuration = 7 days;
        DummyERC721 token = new DummyERC721();
        uint256 tokenId = token.mint(address(impl));
        (
            ,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        ) = _createTestProposal(
            token,
            tokenId,
            listPrice,
            listDuration,
            new uint256[](0),
            new address payable[](0)
        );
        // This will skip zora and list directly on OS because the token is not precious.
        uint256 listStartTime = block.timestamp;
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        bytes32 orderHash;
        {
            (, orderHash,) = abi.decode(executeParams.progressData, (
                ListOnOpenSeaportProposal.ListOnOpenSeaportStep,
                bytes32,
                uint256
            ));
        }
        // Buy the OS listing.
        _buyOpenSeaportListing(BuyOpenSeaportListingParams({
            maker: payable(impl),
            buyer: buyer,
            token: token,
            tokenId: tokenId,
            listPrice: listPrice,
            startTime: listStartTime,
            duration: listDuration,
            zone: SEAPORT_ZONE,
            conduitKey: SEAPORT_CONDUIT_KEY
        }));
        // Finalize the listing.
        vm.expectEmit(false, false, false, true);
        emit OpenSeaportOrderSold(orderHash, token, tokenId, listPrice);
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        assertEq(executeParams.progressData.length, 0);
        // Buyer should own the NFT.
        assertEq(token.ownerOf(tokenId), buyer);
        // Proposal contract should have the list price.
        assertEq(address(impl).balance, LIST_PRICE);
    }

    // Test a proposal where the zora listing expires and the
    // OS listing also expires.
    function testForked_Execution_AllExpiring() public onlyForked {
        address buyer = _randomAddress();
        uint256 listPrice = 1e18;
        uint40 listDuration = 7 days;
        (IERC721 token, uint256 tokenId) = _randomPreciousToken();
        (
            ,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        ) = _createTestProposal(
            token,
            tokenId,
            listPrice,
            listDuration,
            new uint256[](0),
            new address payable[](0)
        );
        // This will list on zora because the proposal was not passed unanimously.
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        // Timeeout the zora listing.
        skip(ZORA_AUCTION_TIMEOUT);
        // Next, retrieve from zora and list on OS.
        uint256 listStartTime = block.timestamp;
        vm.expectEmit(false, false, false, true);
        emit ZoraAuctionExpired(_getNextZoraAuctionId() - 1, block.timestamp);
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        bytes32 orderHash;
        uint256 expiry;
        {
            (, orderHash, expiry) = abi.decode(executeParams.progressData, (
                ListOnOpenSeaportProposal.ListOnOpenSeaportStep,
                bytes32,
                uint256
            ));
        }
        // Skip past expiration.
        skip(listDuration);
        // Attempt to buy the listing (fail).
        vm.expectRevert(ISeaportExchange.InvalidTime.selector);
        _buyOpenSeaportListing(BuyOpenSeaportListingParams({
            maker: payable(impl),
            buyer: buyer,
            token: token,
            tokenId: tokenId,
            listPrice: listPrice,
            startTime: listStartTime,
            duration: listDuration,
            zone: SEAPORT_ZONE,
            conduitKey: SEAPORT_CONDUIT_KEY
        }));
        // Finalize the listing.
        vm.expectEmit(false, false, false, true);
        emit OpenSeaportOrderExpired(orderHash, token, tokenId, expiry);
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        assertEq(executeParams.progressData.length, 0);
        // We should still own the NFT.
        assertEq(token.ownerOf(tokenId), address(impl));
        // Seaport should not have an allowance.
        assertEq(token.getApproved(tokenId), address(0));
    }

    // Test a proposal where the zora listing is bought.
    function testForked_Execution_BoughtOnZora() public onlyForked {
        address buyer = _randomAddress();
        uint256 listPrice = 1e18;
        uint40 listDuration = 7 days;
        (IERC721 token, uint256 tokenId) = _randomPreciousToken();
        (
            ,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        ) = _createTestProposal(
            token,
            tokenId,
            listPrice,
            listDuration,
            new uint256[](0),
            new address payable[](0)
        );
        // This will list on zora because the proposal was not passed unanimously.
        uint256 auctionId = _getNextZoraAuctionId();
        vm.expectEmit(false, false, false, true);
        emit ZoraAuctionCreated(
            auctionId,
            token,
            tokenId,
            listPrice,
            uint40(ZORA_AUCTION_DURATION),
            uint40(block.timestamp) + uint40(ZORA_AUCTION_TIMEOUT)
        );
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        {
            (, ZoraHelpers.ZoraProgressData memory progressData) =
                abi.decode(executeParams.progressData, (
                    ListOnOpenSeaportProposal.ListOnOpenSeaportStep,
                    ZoraHelpers.ZoraProgressData
                ));
            assertEq(progressData.auctionId, auctionId);
        }
        // Try to advance the proposal before the zora auction has timed out (fail).
        skip(ZORA_AUCTION_TIMEOUT- 1);
        vm.expectRevert(abi.encodeWithSelector(
            ListOnZoraProposal.ZoraListingNotExpired.selector,
            auctionId,
            block.timestamp + 1
        ));
        impl.executeListOnOpenSeaport(executeParams);

        // Bid on the zora auction.
        _bidOnZoraListing(auctionId, buyer, listPrice);
        // The auction will be now extended by ZORA_AUCTION_DURATION.

        // Try to advance the proposal before the zora auction has ended (fail).
        skip(ZORA_AUCTION_DURATION - 1);
        vm.expectRevert("Auction hasn't completed");
        impl.executeListOnOpenSeaport(executeParams);

        // Skip past the end of the auction.
        skip(1);
        // Advance the proposal, finalizing the zora auction.
        vm.expectEmit(false, false, false, true);
        emit ZoraAuctionSold(auctionId);
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        assertEq(executeParams.progressData.length, 0);
        // Buyer should own the NFT.
        assertEq(token.ownerOf(tokenId), buyer);
        // Proposal contract should have the bid price.
        assertEq(address(impl).balance, LIST_PRICE);
    }

    // Test a proposal where the zora listing is bought and finalized externally.
    function testForked_Execution_BoughtOnZora_settledExternally() public onlyForked {
        address buyer = _randomAddress();
        uint256 listPrice = 1e18;
        uint40 listDuration = 7 days;
        (IERC721 token, uint256 tokenId) = _randomPreciousToken();
        (
            ,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        ) = _createTestProposal(
            token,
            tokenId,
            listPrice,
            listDuration,
            new uint256[](0),
            new address payable[](0)
        );
        // This will list on zora because the proposal was not passed unanimously.
        uint256 auctionId = _getNextZoraAuctionId();
        vm.expectEmit(false, false, false, true);
        emit ZoraAuctionCreated(
            auctionId,
            token,
            tokenId,
            listPrice,
            uint40(ZORA_AUCTION_DURATION),
            uint40(block.timestamp) + uint40(ZORA_AUCTION_TIMEOUT)
        );
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        {
            (, ZoraHelpers.ZoraProgressData memory progressData) =
                abi.decode(executeParams.progressData, (
                    ListOnOpenSeaportProposal.ListOnOpenSeaportStep,
                    ZoraHelpers.ZoraProgressData
                ));
            assertEq(progressData.auctionId, auctionId);
        }
        // Bid on the zora auction.
        _bidOnZoraListing(auctionId, buyer, listPrice);
        // The auction will be now extended by ZORA_AUCTION_DURATION.
        // Skip past the end of the auction.
        skip(ZORA_AUCTION_DURATION);
        // Settle externally.
        ZORA.endAuction(auctionId);

        // Advance the proposal, finalizing the zora auction.
        vm.expectEmit(false, false, false, true);
        emit ZoraAuctionSold(auctionId);
        executeParams.progressData = impl.executeListOnOpenSeaport(executeParams);
        assertEq(executeParams.progressData.length, 0);
        // Buyer should own the NFT.
        assertEq(token.ownerOf(tokenId), buyer);
        // Proposal contract should have the bid price.
        assertEq(address(impl).balance, LIST_PRICE);
    }
}
