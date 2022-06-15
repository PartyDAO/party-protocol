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
        assert(SEAPORT.fulfillBasicOrder{ value: 1e18 }(_createBasicOpenSeaportOrderParams(
            maker,
            token,
            tokenId,
            listPrice,
            startTime,
            duration
        )));
    }

    function _createBasicOpenSeaportOrderParams(
        address payable maker,
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice,
        uint256 startTime,
        uint256 duration

    )
        private
        pure
        returns (ISeaportExchange.BasicOrderParameters memory params)
    {
        params.basicOrderType = ISeaportExchange.BasicOrderType.ETH_TO_ERC721_FULL_OPEN;
        params.offerer = maker;
        params.offerToken = address(token);
        params.offerIdentifier = tokenId;
        params.offerAmount = 1;
        params.considerationAmount = listPrice;
        params.startTime = startTime;
        params.endTime = startTime + duration;
    }
}
