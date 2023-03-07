// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/ListOnOpenseaProposal.sol";
import "../../contracts/proposals/vendor/IOpenseaExchange.sol";
import "../../contracts/tokens/IERC721.sol";

contract OpenseaTestUtils is Test {
    IOpenseaExchange private immutable SEAPORT;

    constructor(IOpenseaExchange seaport) {
        SEAPORT = seaport;
    }

    struct BuyOpenseaListingParams {
        address payable maker;
        address buyer;
        ListOnOpenseaAdvancedProposal.TokenType tokenType;
        address token;
        uint256 tokenId;
        uint256 listPrice;
        uint256 startTime;
        uint256 duration;
        address zone;
        bytes32 conduitKey;
    }

    struct DutchAuctionOpenseaListingParams {
        address payable maker;
        IERC721 token;
        uint256 tokenId;
        uint256 startPrice;
        uint256 endPrice;
        uint256 startTime;
        uint256 duration;
        address zone;
        bytes32 conduitKey;
    }

    function _buyOpenseaListing(BuyOpenseaListingParams memory params) internal {
        vm.deal(params.buyer, address(params.buyer).balance + params.listPrice);
        vm.prank(params.buyer);
        SEAPORT.fulfillOrder{ value: params.listPrice }(
            _createFullOpenseaOrderParams(params, new uint256[](0), new address payable[](0)),
            0
        );
    }

    function _buyOpenseaListing(
        BuyOpenseaListingParams memory params,
        uint256[] memory fees,
        address payable[] memory feeRecipients
    ) internal {
        uint256 totalValue = params.listPrice;
        for (uint256 i; i < fees.length; ++i) {
            totalValue += fees[i];
        }
        vm.deal(params.buyer, address(params.buyer).balance + totalValue);
        vm.prank(params.buyer);
        SEAPORT.fulfillOrder{ value: totalValue }(
            _createFullOpenseaOrderParams(params, fees, feeRecipients),
            0
        );
    }

    function _createFullOpenseaOrderParams(
        BuyOpenseaListingParams memory params,
        uint256[] memory fees,
        address payable[] memory feeRecipients
    ) internal pure returns (IOpenseaExchange.Order memory order) {
        order.parameters.salt = uint256(bytes32(bytes4(keccak256("partyprotocol"))));
        order.parameters.orderType = params.zone == address(0)
            ? IOpenseaExchange.OrderType.FULL_OPEN
            : IOpenseaExchange.OrderType.FULL_RESTRICTED;
        IOpenseaExchange.OfferItem[] memory offers = order
            .parameters
            .offer = new IOpenseaExchange.OfferItem[](1);
        offers[0].itemType = params.tokenType == ListOnOpenseaAdvancedProposal.TokenType.ERC721
            ? IOpenseaExchange.ItemType.ERC721
            : IOpenseaExchange.ItemType.ERC1155;
        offers[0].token = address(params.token);
        offers[0].identifierOrCriteria = params.tokenId;
        offers[0].startAmount = offers[0].endAmount = 1;
        IOpenseaExchange.ConsiderationItem[] memory considerations = order
            .parameters
            .consideration = new IOpenseaExchange.ConsiderationItem[](1 + fees.length);
        considerations[0].itemType = IOpenseaExchange.ItemType.NATIVE;
        considerations[0].token = address(0);
        considerations[0].identifierOrCriteria = 0;
        considerations[0].startAmount = considerations[0].endAmount = params.listPrice;
        considerations[0].recipient = params.maker;
        for (uint256 i; i < fees.length; ++i) {
            considerations[1 + i].itemType = IOpenseaExchange.ItemType.NATIVE;
            considerations[1 + i].token = address(0);
            considerations[1 + i].identifierOrCriteria = 0;
            considerations[1 + i].startAmount = considerations[1 + i].endAmount = fees[i];
            considerations[1 + i].recipient = feeRecipients[i];
        }
        order.parameters.offerer = params.maker;
        order.parameters.startTime = params.startTime;
        order.parameters.endTime = params.startTime + params.duration;
        order.parameters.totalOriginalConsiderationItems = 1 + fees.length;
        order.parameters.conduitKey = params.conduitKey;
        order.parameters.zone = params.zone;
    }

    function _createFullOpenseaOrderParams(
        BuyOpenseaListingParams memory params
    ) internal pure returns (IOpenseaExchange.Order memory order) {
        return _createFullOpenseaOrderParams(params, new uint256[](0), new address payable[](0));
    }

    function _createOpenseaDutchAuctionOrderParams(
        DutchAuctionOpenseaListingParams memory params,
        uint256[] memory fees,
        address payable[] memory feeRecipients
    ) internal pure returns (IOpenseaExchange.Order memory order) {
        order.parameters.salt = uint256(bytes32(bytes4(keccak256("partyprotocol"))));
        order.parameters.orderType = params.zone == address(0)
            ? IOpenseaExchange.OrderType.FULL_OPEN
            : IOpenseaExchange.OrderType.FULL_RESTRICTED;
        IOpenseaExchange.OfferItem[] memory offers = order
            .parameters
            .offer = new IOpenseaExchange.OfferItem[](1);
        offers[0].itemType = IOpenseaExchange.ItemType.ERC721;
        offers[0].token = address(params.token);
        offers[0].identifierOrCriteria = params.tokenId;
        offers[0].startAmount = offers[0].endAmount = 1;
        IOpenseaExchange.ConsiderationItem[] memory considerations = order
            .parameters
            .consideration = new IOpenseaExchange.ConsiderationItem[](1 + fees.length);
        considerations[0].itemType = IOpenseaExchange.ItemType.NATIVE;
        considerations[0].token = address(0);
        considerations[0].identifierOrCriteria = 0;
        considerations[0].startAmount = params.startPrice;
        considerations[0].endAmount = params.endPrice;
        considerations[0].recipient = params.maker;
        for (uint256 i; i < fees.length; ++i) {
            considerations[1 + i].itemType = IOpenseaExchange.ItemType.NATIVE;
            considerations[1 + i].token = address(0);
            considerations[1 + i].identifierOrCriteria = 0;
            considerations[1 + i].startAmount = considerations[1 + i].endAmount = fees[i];
            considerations[1 + i].recipient = feeRecipients[i];
        }
        order.parameters.offerer = params.maker;
        order.parameters.startTime = params.startTime;
        order.parameters.endTime = params.startTime + params.duration;
        order.parameters.totalOriginalConsiderationItems = 1 + fees.length;
        order.parameters.conduitKey = params.conduitKey;
        order.parameters.zone = params.zone;
    }

    function _createOpenseaDutchAuctionOrderParams(
        DutchAuctionOpenseaListingParams memory params
    ) internal pure returns (IOpenseaExchange.Order memory order) {
        return
            _createOpenseaDutchAuctionOrderParams(
                params,
                new uint256[](0),
                new address payable[](0)
            );
    }
}
