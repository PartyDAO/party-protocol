// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/ListOnOpenSeaportProposal.sol";
import "../../contracts/proposals/ListOnZoraProposal.sol";
import "../../contracts/tokens/ERC721Receiver.sol";

contract TestableListOnOpenSeaportProposal is
    ListOnOpenSeaportProposal,
    ListOnZoraProposal,
    ERC721Receiver
{
    constructor(
        IGlobals globals,
        ISeaportExchange seaport,
        ISeaportConduitController conduitController,
        IZoraAuctionHouse zora
    )
        ListOnOpenSeaportProposal(globals, seaport, conduitController)
        ListOnZoraProposal(zora)
    {}

    receive() external payable {}

    function executeListOnOpenSeaport(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    )
        public
        returns (bytes memory nextProgressData)
    {
        return _executeListOnOpenSeaport(params);
    }
}
