// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/ListOnOpenSeaProposal.sol";
import "../../contracts/tokens/IERC721Receiver.sol";

contract TestableListOnOpenSeaProposal is ListOnOpenSeaProposal {
    constructor(IGlobals globals, SharedWyvernV2Maker maker, IZoraAuctionHouse zora)
        ListOnOpenSeaProposal(globals, maker, zora)
    {}

    function executeListOnOpenSea(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    )
        public
        returns (bytes memory nextProgressData)
    {
        return _executeListOnOpenSea(params);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    )
        external
        virtual
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
}
