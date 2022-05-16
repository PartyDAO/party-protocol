// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/ListOnOpenSeaProposal.sol";
import "../../contracts/tokens/ERC721Receiver.sol";

contract TestableListOnOpenSeaProposal is ListOnOpenSeaProposal, ERC721Receiver {
    constructor(IGlobals globals, SharedWyvernV2Maker maker, IZoraAuctionHouse zora)
        ListOnOpenSeaProposal(globals, maker, zora)
    {}

    fallback() external payable {}

    function executeListOnOpenSea(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    )
        public
        returns (bytes memory nextProgressData)
    {
        return _executeListOnOpenSea(params);
    }
}
