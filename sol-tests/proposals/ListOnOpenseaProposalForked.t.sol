// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/proposals/vendor/IOpenseaExchange.sol";

import "../TestUtils.sol";
import "../DummyERC721.sol";
import "../DummyERC1155.sol";
import "./TestableListOnOpenseaProposal.sol";
import "./ZoraTestUtils.sol";
import "./OpenseaTestUtils.sol";

contract ListOnOpenseaProposalForkedTest is Test, TestUtils, ZoraTestUtils, OpenseaTestUtils {
    event OpenseaOrderListed(
        IOpenseaExchange.OrderParameters orderParams,
        bytes32 orderHash,
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice,
        uint256 expiry
    );
    event OpenseaAdvancedOrderListed(
        IOpenseaExchange.OrderParameters orderParams,
        bytes32 orderHash,
        address token,
        uint256 tokenId,
        uint256 startPrice,
        uint256 endPrice,
        uint256 expiry
    );
    event OpenseaOrderSold(bytes32 orderHash, IERC721 token, uint256 tokenId, uint256 listPrice);
    event OpenseaAdvancedOrderSold(
        bytes32 orderHash,
        address token,
        uint256 tokenId,
        uint256 startPrice,
        uint256 endPrice
    );
    event OpenseaOrderExpired(bytes32 orderHash, address token, uint256 tokenId, uint256 expiry);
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
    event ZoraAuctionFailed(uint256 auctionId);

    uint256 constant ZORA_AUCTION_DURATION = 0.5 days;
    uint256 constant ZORA_AUCTION_TIMEOUT = 1 days;
    uint256 constant LIST_PRICE = 1e18;
    TestableListOnOpenseaProposal impl;
    Globals globals;
    IOpenseaExchange SEAPORT = IOpenseaExchange(0x00000000006c3852cbEf3e08E8dF289169EdE581);
    IOpenseaConduitController CONDUIT_CONTROLLER =
        IOpenseaConduitController(0x00000000F9490004C11Cef243f5400493c00Ad63);
    IZoraAuctionHouse ZORA = IZoraAuctionHouse(0xE468cE99444174Bd3bBBEd09209577d25D1ad673);
    address SEAPORT_ZONE = 0x004C00500000aD104D7DBd00e3ae0A5C00560C00;
    bytes32 SEAPORT_CONDUIT_KEY =
        0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000;
    IERC721[] preciousTokens;
    uint256[] preciousTokenIds;

    constructor() ZoraTestUtils(ZORA) OpenseaTestUtils(SEAPORT) {}

    function setUp() public onlyForked {
        globals = new Globals(address(this));
        globals.setBytes32(LibGlobals.GLOBAL_OPENSEA_CONDUIT_KEY, SEAPORT_CONDUIT_KEY);
        globals.setAddress(LibGlobals.GLOBAL_OPENSEA_ZONE, SEAPORT_ZONE);
        globals.setUint256(LibGlobals.GLOBAL_OS_ZORA_AUCTION_TIMEOUT, ZORA_AUCTION_TIMEOUT);
        globals.setUint256(LibGlobals.GLOBAL_OS_ZORA_AUCTION_DURATION, ZORA_AUCTION_DURATION);
        globals.setUint256(LibGlobals.GLOBAL_OS_MIN_ORDER_DURATION, 1 days);
        globals.setUint256(LibGlobals.GLOBAL_OS_MAX_ORDER_DURATION, 7 days);
        impl = new TestableListOnOpenseaProposal(globals, SEAPORT, CONDUIT_CONTROLLER, ZORA);
        (preciousTokens, preciousTokenIds) = _createPreciousTokens(address(impl), 2);
    }

    function _createPreciousTokens(
        address owner,
        uint256 count
    ) private returns (IERC721[] memory tokens, uint256[] memory tokenIds) {
        tokens = new IERC721[](count);
        tokenIds = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            DummyERC721 t = new DummyERC721();
            tokens[i] = t;
            tokenIds[i] = t.mint(owner);
        }
    }

    function _createProposal(
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
            ListOnOpenseaProposal.OpenseaProposalData memory proposalData,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        )
    {
        proposalData = ListOnOpenseaProposal.OpenseaProposalData({
            listPrice: listPrice,
            duration: duration,
            token: token,
            tokenId: tokenId,
            fees: fees,
            feeRecipients: feeRecipients,
            domainHashPrefix: bytes4(keccak256("partyprotocol"))
        });
        executeParams = IProposalExecutionEngine.ExecuteProposalParams({
            proposalId: _randomUint256(),
            proposalData: abi.encode(proposalData),
            progressData: "",
            extraData: "",
            flags: 0,
            preciousTokens: preciousTokens,
            preciousTokenIds: preciousTokenIds
        });
    }

    function _createAdvancedProposal(
        ListOnOpenseaAdvancedProposal.TokenType tokenType,
        address token,
        uint256 tokenId,
        uint256 startPrice,
        uint256 endPrice,
        uint40 duration,
        uint256[] memory fees,
        address payable[] memory feeRecipients
    )
        private
        view
        returns (
            ListOnOpenseaAdvancedProposal.OpenseaAdvancedProposalData memory proposalData,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        )
    {
        proposalData = ListOnOpenseaAdvancedProposal.OpenseaAdvancedProposalData({
            startPrice: startPrice,
            endPrice: endPrice,
            duration: duration,
            tokenType: tokenType,
            token: token,
            tokenId: tokenId,
            fees: fees,
            feeRecipients: feeRecipients,
            domainHashPrefix: bytes4(keccak256("partyprotocol"))
        });
        executeParams = IProposalExecutionEngine.ExecuteProposalParams({
            proposalId: _randomUint256(),
            proposalData: abi.encode(proposalData),
            progressData: "",
            extraData: "",
            flags: 0,
            preciousTokens: preciousTokens,
            preciousTokenIds: preciousTokenIds
        });
    }

    function _generateOrderParams(
        ListOnOpenseaProposal.OpenseaProposalData memory data
    ) private view returns (IOpenseaExchange.OrderParameters memory orderParams) {
        return
            _generateOrderParams(
                ListOnOpenseaAdvancedProposal.OpenseaAdvancedProposalData({
                    startPrice: data.listPrice,
                    endPrice: data.listPrice,
                    duration: data.duration,
                    tokenType: ListOnOpenseaAdvancedProposal.TokenType.ERC721,
                    token: address(data.token),
                    tokenId: data.tokenId,
                    fees: data.fees,
                    feeRecipients: data.feeRecipients,
                    domainHashPrefix: data.domainHashPrefix
                })
            );
    }

    function _generateOrderParams(
        ListOnOpenseaAdvancedProposal.OpenseaAdvancedProposalData memory data
    ) private view returns (IOpenseaExchange.OrderParameters memory orderParams) {
        orderParams.offerer = address(impl);
        orderParams.startTime = block.timestamp;
        orderParams.endTime = block.timestamp + uint256(data.duration);
        orderParams.zone = globals.getAddress(LibGlobals.GLOBAL_OPENSEA_ZONE);
        orderParams.orderType = orderParams.zone == address(0)
            ? IOpenseaExchange.OrderType.FULL_OPEN
            : IOpenseaExchange.OrderType.FULL_RESTRICTED;
        orderParams.salt = uint256(bytes32(data.domainHashPrefix));
        orderParams.conduitKey = globals.getBytes32(LibGlobals.GLOBAL_OPENSEA_CONDUIT_KEY);
        orderParams.totalOriginalConsiderationItems = 1 + data.fees.length;
        // What we are selling.
        orderParams.offer = new IOpenseaExchange.OfferItem[](1);
        {
            IOpenseaExchange.OfferItem memory offer = orderParams.offer[0];
            offer.itemType = IOpenseaExchange.ItemType.ERC721;
            offer.token = address(data.token);
            offer.identifierOrCriteria = data.tokenId;
            offer.startAmount = 1;
            offer.endAmount = 1;
        }
        // What we want for it.
        orderParams.consideration = new IOpenseaExchange.ConsiderationItem[](1 + data.fees.length);
        {
            IOpenseaExchange.ConsiderationItem memory cons = orderParams.consideration[0];
            cons.itemType = IOpenseaExchange.ItemType.NATIVE;
            cons.token = address(0);
            cons.identifierOrCriteria = 0;
            cons.startAmount = data.startPrice;
            cons.endAmount = data.endPrice;
            cons.recipient = payable(address(impl));
            for (uint256 i; i < data.fees.length; ++i) {
                cons = orderParams.consideration[1 + i];
                cons.itemType = IOpenseaExchange.ItemType.NATIVE;
                cons.token = address(0);
                cons.identifierOrCriteria = 0;
                cons.startAmount = data.fees[i];
                cons.endAmount = (data.fees[i] * data.endPrice) / data.startPrice;
                cons.recipient = data.feeRecipients[i];
            }
        }
    }

    function _getOrderHash(
        IOpenseaExchange.OrderParameters memory orderParams
    ) private view returns (bytes32 orderHash) {
        // getOrderHash() wants an OrderComponents struct, which is an OrderParameters
        // struct but with the last field (totalOriginalConsiderationItems)
        // replaced with the maker's nonce. Since we (the maker) never increment
        // our seaport nonce, it is always 0.
        // So we temporarily set the totalOriginalConsiderationItems field to 0,
        // force cast the OrderParameters into a OrderComponents type, call
        // getOrderHash(), and then restore the totalOriginalConsiderationItems
        // field's value before returning.
        uint256 origTotalOriginalConsiderationItems = orderParams.totalOriginalConsiderationItems;
        orderParams.totalOriginalConsiderationItems = 0;
        IOpenseaExchange.OrderComponents memory orderComps;
        assembly {
            orderComps := orderParams
        }
        orderHash = SEAPORT.getOrderHash(orderComps);
        orderParams.totalOriginalConsiderationItems = origTotalOriginalConsiderationItems;
    }

    function _randomPreciousToken() private view returns (IERC721 token, uint256 tokenId) {
        uint256 idx = _randomRange(0, preciousTokens.length);
        return (preciousTokens[idx], preciousTokenIds[idx]);
    }

    function testForked_Execution_durationBounds() public onlyForked {
        uint256 listPrice = 1e18;
        uint40 listDuration = 7 days;
        (IERC721 token, uint256 tokenId) = _randomPreciousToken();
        (
            ListOnOpenseaProposal.OpenseaProposalData memory data,
            IProposalExecutionEngine.ExecuteProposalParams memory params
        ) = _createProposal(
                token,
                tokenId,
                listPrice,
                listDuration,
                new uint256[](0),
                new address payable[](0)
            );
        // Skip to relevant step
        params.progressData = abi.encode(
            ListOnOpenseaAdvancedProposal.ListOnOpenseaStep.RetrievedFromZora
        );

        // Test minimum order duration is enforced
        uint40 minDuration = uint40(globals.getUint256(LibGlobals.GLOBAL_OS_MIN_ORDER_DURATION));
        data.duration = minDuration;
        IOpenseaExchange.OrderParameters memory orderParams = _generateOrderParams(data);
        bytes32 orderHash = _getOrderHash(orderParams);

        data.duration = minDuration / 2;
        params.proposalData = abi.encode(data);

        _expectEmit0();
        emit OpenseaOrderListed(
            orderParams,
            orderHash,
            token,
            tokenId,
            listPrice,
            uint40(block.timestamp) + minDuration
        );
        impl.executeListOnOpensea(params);

        // Test maximum order duration is enforced
        uint40 maxDuration = uint40(globals.getUint256(LibGlobals.GLOBAL_OS_MAX_ORDER_DURATION));
        data.duration = maxDuration;
        orderParams = _generateOrderParams(data);
        orderHash = _getOrderHash(orderParams);

        data.duration = maxDuration * 2;
        params.proposalData = abi.encode(data);

        _expectEmit0();
        emit OpenseaOrderListed(
            orderParams,
            orderHash,
            token,
            tokenId,
            listPrice,
            uint40(block.timestamp) + maxDuration
        );
        impl.executeListOnOpensea(params);
    }

    // Test a proposal where the zora listing times out and the
    // OS listing gets bought.
    function testForked_Execution_OSBought() public onlyForked {
        address buyer = _randomAddress();
        uint256 listPrice = 1e18;
        uint40 listDuration = 7 days;
        (IERC721 token, uint256 tokenId) = _randomPreciousToken();
        (, IProposalExecutionEngine.ExecuteProposalParams memory executeParams) = _createProposal(
            token,
            tokenId,
            listPrice,
            listDuration,
            new uint256[](0),
            new address payable[](0)
        );
        // This will list on zora because the proposal was not passed unanimously.
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
        // Time out the zora listing.
        skip(ZORA_AUCTION_TIMEOUT);
        // Next, retrieve from zora and list on OS.
        uint256 listStartTime = block.timestamp;
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
        bytes32 orderHash;
        {
            (, orderHash, ) = abi.decode(
                executeParams.progressData,
                (ListOnOpenseaAdvancedProposal.ListOnOpenseaStep, bytes32, uint256)
            );
        }
        // Buy the OS listing.
        _buyOpenseaListing(
            BuyOpenseaListingParams({
                maker: payable(impl),
                buyer: buyer,
                tokenType: ListOnOpenseaAdvancedProposal.TokenType.ERC721,
                token: address(token),
                tokenId: tokenId,
                listPrice: listPrice,
                startTime: listStartTime,
                duration: listDuration,
                zone: SEAPORT_ZONE,
                conduitKey: SEAPORT_CONDUIT_KEY
            })
        );
        // Finalize the listing.
        vm.expectEmit(false, false, false, true);
        emit OpenseaOrderSold(orderHash, token, tokenId, listPrice);
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
        assertEq(executeParams.progressData.length, 0);
        // Buyer should own the NFT.
        assertEq(token.ownerOf(tokenId), buyer);
        // Proposal contract should have the list price.
        assertEq(address(impl).balance, LIST_PRICE);
    }

    function testForked_Execution_OSBought_ListingERC1155() public onlyForked {
        address buyer = _randomAddress();
        uint256 listPrice = 1e18;
        uint40 listDuration = 7 days;
        DummyERC1155 token = new DummyERC1155();
        uint256 tokenId = _randomUint256();
        token.deal(address(impl), tokenId, 1);
        (
            ,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        ) = _createAdvancedProposal(
                ListOnOpenseaAdvancedProposal.TokenType.ERC1155,
                address(token),
                tokenId,
                listPrice,
                listPrice,
                listDuration,
                new uint256[](0),
                new address payable[](0)
            );
        // List on OS
        uint256 listStartTime = block.timestamp;
        executeParams.progressData = impl.executeListOnOpenseaAdvanced(executeParams);
        bytes32 orderHash;
        {
            (, orderHash, ) = abi.decode(
                executeParams.progressData,
                (ListOnOpenseaAdvancedProposal.ListOnOpenseaStep, bytes32, uint256)
            );
        }
        // Buy the OS listing.
        _buyOpenseaListing(
            BuyOpenseaListingParams({
                maker: payable(impl),
                buyer: buyer,
                tokenType: ListOnOpenseaAdvancedProposal.TokenType.ERC1155,
                token: address(token),
                tokenId: tokenId,
                listPrice: listPrice,
                startTime: listStartTime,
                duration: listDuration,
                zone: SEAPORT_ZONE,
                conduitKey: SEAPORT_CONDUIT_KEY
            })
        );
        // Finalize the listing.
        vm.expectEmit(false, false, false, true);
        emit OpenseaAdvancedOrderSold(orderHash, address(token), tokenId, listPrice, listPrice);
        executeParams.progressData = impl.executeListOnOpenseaAdvanced(executeParams);
        assertEq(executeParams.progressData.length, 0);
        // Buyer should own the NFT.
        assertEq(token.balanceOf(buyer, tokenId), 1);
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
        (, IProposalExecutionEngine.ExecuteProposalParams memory executeParams) = _createProposal(
            token,
            tokenId,
            listPrice,
            listDuration,
            fees,
            feeRecipients
        );
        // This will list on zora because the proposal was not passed unanimously.
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
        // Time out the zora listing.
        skip(ZORA_AUCTION_TIMEOUT);
        // Next, retrieve from zora and list on OS.
        uint256 listStartTime = block.timestamp;
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
        bytes32 orderHash;
        {
            (, orderHash, ) = abi.decode(
                executeParams.progressData,
                (ListOnOpenseaAdvancedProposal.ListOnOpenseaStep, bytes32, uint256)
            );
        }
        // Buy the OS listing.
        _buyOpenseaListing(
            BuyOpenseaListingParams({
                maker: payable(impl),
                buyer: buyer,
                tokenType: ListOnOpenseaAdvancedProposal.TokenType.ERC721,
                token: address(token),
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
        emit OpenseaOrderSold(orderHash, token, tokenId, listPrice);
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
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
        (, IProposalExecutionEngine.ExecuteProposalParams memory executeParams) = _createProposal(
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
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
        bytes32 orderHash;
        {
            (, orderHash, ) = abi.decode(
                executeParams.progressData,
                (ListOnOpenseaAdvancedProposal.ListOnOpenseaStep, bytes32, uint256)
            );
        }
        // Buy the OS listing.
        _buyOpenseaListing(
            BuyOpenseaListingParams({
                maker: payable(impl),
                buyer: buyer,
                tokenType: ListOnOpenseaAdvancedProposal.TokenType.ERC721,
                token: address(token),
                tokenId: tokenId,
                listPrice: listPrice,
                startTime: listStartTime,
                duration: listDuration,
                zone: SEAPORT_ZONE,
                conduitKey: SEAPORT_CONDUIT_KEY
            })
        );
        // Finalize the listing.
        vm.expectEmit(false, false, false, true);
        emit OpenseaOrderSold(orderHash, token, tokenId, listPrice);
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
        assertEq(executeParams.progressData.length, 0);
        // Buyer should own the NFT.
        assertEq(token.ownerOf(tokenId), buyer);
        // Proposal contract should have the list price.
        assertEq(address(impl).balance, LIST_PRICE);
    }

    function testForked_Execution_OSDutchAuctionListing() public onlyForked {
        address buyer = _randomAddress();
        uint256 startPrice = 3e18;
        uint256 endPrice = 1e18;
        uint40 listDuration = 7 days;
        uint256[] memory fees = new uint256[](1);
        fees[0] = 0.3e18;
        address payable[] memory feeRecipients = new address payable[](1);
        feeRecipients[0] = _randomAddress();
        (IERC721 token, uint256 tokenId) = _randomPreciousToken();
        (
            ListOnOpenseaAdvancedProposal.OpenseaAdvancedProposalData memory data,
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        ) = _createAdvancedProposal(
                ListOnOpenseaAdvancedProposal.TokenType.ERC721,
                address(token),
                tokenId,
                startPrice,
                endPrice,
                listDuration,
                fees,
                feeRecipients
            );
        // This will list on zora because the proposal was not passed unanimously.
        executeParams.progressData = impl.executeListOnOpenseaAdvanced(executeParams);
        // Time out the zora listing.
        skip(ZORA_AUCTION_TIMEOUT);
        // Next, retrieve from zora and list on OS.
        executeParams.progressData = impl.executeListOnOpenseaAdvanced(executeParams);
        bytes32 orderHash;
        {
            (, orderHash, ) = abi.decode(
                executeParams.progressData,
                (ListOnOpenseaAdvancedProposal.ListOnOpenseaStep, bytes32, uint256)
            );
        }
        IOpenseaExchange.OrderParameters memory orderParams = _generateOrderParams(data);
        // Skip halfway through dutch auction.
        skip(listDuration / 2);
        // Halfway price between start and end price (including fees).
        uint256 currentPrice = 2.2e18;
        // Buy the OS listing.
        vm.deal(buyer, currentPrice);
        vm.prank(buyer);
        SEAPORT.fulfillOrder{ value: currentPrice }(
            IOpenseaExchange.Order({ parameters: orderParams, signature: "" }),
            0
        );
        // Finalize the listing.
        vm.expectEmit(false, false, false, true);
        emit OpenseaAdvancedOrderSold(orderHash, address(token), tokenId, startPrice, endPrice);
        executeParams.progressData = impl.executeListOnOpenseaAdvanced(executeParams);
        assertEq(executeParams.progressData.length, 0);
        // Buyer should own the NFT.
        assertEq(token.ownerOf(tokenId), buyer);
        // Proposal contract should have the list price.
        assertEq(address(impl).balance, 2e18);
    }

    // Test a proposal for a non-precious token where the OS listing gets bought.
    function testForked_Execution_OSBought_NonPreciousToken() public onlyForked {
        address buyer = _randomAddress();
        uint256 listPrice = 1e18;
        uint40 listDuration = 7 days;
        DummyERC721 token = new DummyERC721();
        uint256 tokenId = token.mint(address(impl));
        (, IProposalExecutionEngine.ExecuteProposalParams memory executeParams) = _createProposal(
            token,
            tokenId,
            listPrice,
            listDuration,
            new uint256[](0),
            new address payable[](0)
        );
        // This will skip zora and list directly on OS because the token is not precious.
        uint256 listStartTime = block.timestamp;
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
        bytes32 orderHash;
        {
            (, orderHash, ) = abi.decode(
                executeParams.progressData,
                (ListOnOpenseaAdvancedProposal.ListOnOpenseaStep, bytes32, uint256)
            );
        }
        // Buy the OS listing.
        _buyOpenseaListing(
            BuyOpenseaListingParams({
                maker: payable(impl),
                buyer: buyer,
                tokenType: ListOnOpenseaAdvancedProposal.TokenType.ERC721,
                token: address(token),
                tokenId: tokenId,
                listPrice: listPrice,
                startTime: listStartTime,
                duration: listDuration,
                zone: SEAPORT_ZONE,
                conduitKey: SEAPORT_CONDUIT_KEY
            })
        );
        // Finalize the listing.
        vm.expectEmit(false, false, false, true);
        emit OpenseaOrderSold(orderHash, token, tokenId, listPrice);
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
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
        (, IProposalExecutionEngine.ExecuteProposalParams memory executeParams) = _createProposal(
            token,
            tokenId,
            listPrice,
            listDuration,
            new uint256[](0),
            new address payable[](0)
        );
        // This will list on zora because the proposal was not passed unanimously.
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
        // Timeeout the zora listing.
        skip(ZORA_AUCTION_TIMEOUT);
        // Next, retrieve from zora and list on OS.
        uint256 listStartTime = block.timestamp;
        vm.expectEmit(false, false, false, true);
        emit ZoraAuctionExpired(_getNextZoraAuctionId() - 1, block.timestamp);
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
        bytes32 orderHash;
        uint256 expiry;
        {
            (, orderHash, , expiry) = abi.decode(
                executeParams.progressData,
                (ListOnOpenseaAdvancedProposal.ListOnOpenseaStep, bytes32, address, uint256)
            );
        }
        // Skip past expiration.
        skip(listDuration);
        // Attempt to buy the listing (fail).
        vm.expectRevert(IOpenseaExchange.InvalidTime.selector);
        _buyOpenseaListing(
            BuyOpenseaListingParams({
                maker: payable(impl),
                buyer: buyer,
                tokenType: ListOnOpenseaAdvancedProposal.TokenType.ERC721,
                token: address(token),
                tokenId: tokenId,
                listPrice: listPrice,
                startTime: listStartTime,
                duration: listDuration,
                zone: SEAPORT_ZONE,
                conduitKey: SEAPORT_CONDUIT_KEY
            })
        );
        // Finalize the listing.
        vm.expectEmit(false, false, false, true);
        emit OpenseaOrderExpired(orderHash, address(token), tokenId, expiry);
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
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
        (, IProposalExecutionEngine.ExecuteProposalParams memory executeParams) = _createProposal(
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
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
        {
            (, ZoraHelpers.ZoraProgressData memory progressData) = abi.decode(
                executeParams.progressData,
                (ListOnOpenseaAdvancedProposal.ListOnOpenseaStep, ZoraHelpers.ZoraProgressData)
            );
            assertEq(progressData.auctionId, auctionId);
        }
        // Try to advance the proposal before the zora auction has timed out (fail).
        skip(ZORA_AUCTION_TIMEOUT - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ListOnZoraProposal.ZoraListingNotExpired.selector,
                auctionId,
                block.timestamp + 1
            )
        );
        impl.executeListOnOpensea(executeParams);

        // Bid on the zora auction.
        _bidOnZoraListing(auctionId, buyer, listPrice);
        // The auction will be now extended by ZORA_AUCTION_DURATION.

        // Try to advance the proposal before the zora auction has ended (fail).
        skip(ZORA_AUCTION_DURATION - 1);
        vm.expectRevert("Auction hasn't completed");
        impl.executeListOnOpensea(executeParams);

        // Skip past the end of the auction.
        skip(1);
        // Advance the proposal, finalizing the zora auction.
        vm.expectEmit(false, false, false, true);
        emit ZoraAuctionSold(auctionId);
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
        assertEq(executeParams.progressData.length, 0);
        // Buyer should own the NFT.
        assertEq(token.ownerOf(tokenId), buyer);
        // Proposal contract should have the bid price.
        assertEq(address(impl).balance, LIST_PRICE);
    }

    // Test a proposal where the zora listing is cancelled.
    function testForked_Execution_BoughtOnZora_Cancelled() public onlyForked {
        // Zroa will cancel the auction during settlement because the buyer cannot receive the NFT.
        address buyer = address(this);
        uint256 listPrice = 1e18;
        uint40 listDuration = 7 days;
        (IERC721 token, uint256 tokenId) = _randomPreciousToken();
        (, IProposalExecutionEngine.ExecuteProposalParams memory executeParams) = _createProposal(
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
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
        {
            (, ZoraHelpers.ZoraProgressData memory progressData) = abi.decode(
                executeParams.progressData,
                (ListOnOpenseaAdvancedProposal.ListOnOpenseaStep, ZoraHelpers.ZoraProgressData)
            );
            assertEq(progressData.auctionId, auctionId);
        }
        // Try to advance the proposal before the zora auction has timed out (fail).
        skip(ZORA_AUCTION_TIMEOUT - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ListOnZoraProposal.ZoraListingNotExpired.selector,
                auctionId,
                block.timestamp + 1
            )
        );
        impl.executeListOnOpensea(executeParams);

        // Bid on the zora auction.
        _bidOnZoraListing(auctionId, buyer, listPrice);
        // The auction will be now extended by ZORA_AUCTION_DURATION.

        // Skip past the end of the auction.
        skip(ZORA_AUCTION_DURATION);
        // Advance the proposal, finalizing the zora auction.
        vm.expectEmit(false, false, false, true);
        emit ZoraAuctionFailed(auctionId);
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
        // Listing cancelled because the buyer could not receive the NFT. The
        // proposal should be done.
        assertEq(executeParams.progressData.length, 0);
    }

    // Test a proposal where the zora listing is bought and finalized externally.
    function testForked_Execution_BoughtOnZora_settledExternally() public onlyForked {
        address buyer = _randomAddress();
        uint256 listPrice = 1e18;
        uint40 listDuration = 7 days;
        (IERC721 token, uint256 tokenId) = _randomPreciousToken();
        (, IProposalExecutionEngine.ExecuteProposalParams memory executeParams) = _createProposal(
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
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
        {
            (, ZoraHelpers.ZoraProgressData memory progressData) = abi.decode(
                executeParams.progressData,
                (ListOnOpenseaAdvancedProposal.ListOnOpenseaStep, ZoraHelpers.ZoraProgressData)
            );
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
        executeParams.progressData = impl.executeListOnOpensea(executeParams);
        assertEq(executeParams.progressData.length, 0);
        // Buyer should own the NFT.
        assertEq(token.ownerOf(tokenId), buyer);
        // Proposal contract should have the bid price.
        assertEq(address(impl).balance, LIST_PRICE);
    }
}
