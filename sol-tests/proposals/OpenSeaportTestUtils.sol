// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/opensea/ISeaportExchange.sol";
import "../../contracts/tokens/IERC721.sol";

contract OpenSeaportTestUtils is Test {

    ISeaportExchange private immutable SEAPORT;

    constructor(ISeaportExchange seaport) {
        SEAPORT = seaport;
    }

    function _buyOpenSeaportListing(
        address payable maker,
        address buyer,
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice,
        uint256 startTime,
        uint256 duration
    )
        internal
    {
        vm.deal(buyer, address(buyer).balance + listPrice);
        vm.prank(buyer);
        SEAPORT.fulfillOrder{ value: listPrice }(_createFullSeaportOrderParams(
            maker,
            token,
            tokenId,
            listPrice,
            startTime,
            duration,
            new uint256[](0),
            new address payable[](0)
        ), 0);
    }

    function _buyOpenSeaportListing(
        address payable maker,
        address buyer,
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice,
        uint256 startTime,
        uint256 duration,
        uint256[] memory fees,
        address payable[] memory feeRecipients
    )
        internal
    {
        uint256 totalValue = listPrice;
        for (uint256 i = 0; i < fees.length; ++i) {
            totalValue += fees[i];
        }
        vm.deal(buyer, address(buyer).balance + totalValue);
        vm.prank(buyer);
        SEAPORT.fulfillOrder{ value: totalValue }(_createFullSeaportOrderParams(
            maker,
            token,
            tokenId,
            listPrice,
            startTime,
            duration,
            fees,
            feeRecipients
        ), 0);
    }

    function _createFullSeaportOrderParams(
        address payable maker,
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice,
        uint256 startTime,
        uint256 duration,
        uint256[] memory fees,
        address payable[] memory feeRecipients
    )
        private
        pure
        returns (ISeaportExchange.Order memory order)
    {
        order.parameters.orderType = ISeaportExchange.OrderType.FULL_OPEN;
        ISeaportExchange.OfferItem[] memory offers =
            order.parameters.offer =
                new ISeaportExchange.OfferItem[](1);
        offers[0].itemType = ISeaportExchange.ItemType.ERC721;
        offers[0].token = address(token);
        offers[0].identifierOrCriteria = tokenId;
        offers[0].startAmount = offers[0].endAmount = 1;
        ISeaportExchange.ConsiderationItem[] memory considerations =
            order.parameters.consideration =
                new ISeaportExchange.ConsiderationItem[](1 + fees.length);
        considerations[0].itemType = ISeaportExchange.ItemType.NATIVE;
        considerations[0].token = address(0);
        considerations[0].identifierOrCriteria = 0;
        considerations[0].startAmount = considerations[0].endAmount = listPrice;
        considerations[0].recipient = maker;
        for (uint256 i = 0; i < fees.length; ++i) {
            considerations[1 + i].itemType = ISeaportExchange.ItemType.NATIVE;
            considerations[1 + i].token = address(0);
            considerations[1 + i].identifierOrCriteria = 0;
            considerations[1 + i].startAmount = considerations[1 + i].endAmount = fees[i];
            considerations[1 + i].recipient = feeRecipients[i];
        }
        order.parameters.offerer = maker;
        order.parameters.startTime = startTime;
        order.parameters.endTime = startTime + duration;
        order.parameters.totalOriginalConsiderationItems = 1 + fees.length;
    }
}
