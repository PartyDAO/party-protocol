// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/ListOnSeaportProposal.sol";
import "../../contracts/proposals/ListOnZoraProposal.sol";
import "../../contracts/tokens/ERC721Receiver.sol";

contract TestableListOnSeaportProposal is
    ListOnSeaportProposal,
    ListOnZoraProposal,
    ERC721Receiver
{
    constructor(
        IGlobals globals,
        ISeaportExchange seaport,
        ISeaportConduitController conduitController,
        IZoraAuctionHouse zora
    )
        ListOnSeaportProposal(globals, seaport, conduitController)
        ListOnZoraProposal(globals, zora)
    {}

    receive() external payable {}

    function executeListOnSeaport(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    )
        public
        returns (bytes memory nextProgressData)
    {
        return _executeListOnSeaport(params);
    }
}
