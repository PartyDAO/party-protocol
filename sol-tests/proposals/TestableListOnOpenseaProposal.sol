// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/ListOnOpenseaProposal.sol";
import "../../contracts/proposals/ListOnZoraProposal.sol";
import "../../contracts/tokens/ERC721Receiver.sol";

contract TestableListOnOpenseaProposal is
    ListOnOpenseaProposal,
    ListOnZoraProposal,
    ERC721Receiver
{
    constructor(
        IGlobals globals,
        IOpenseaExchange seaport,
        IOpenseaConduitController conduitController,
        IZoraAuctionHouse zora
    )
        ListOnOpenseaProposal(globals, seaport, conduitController)
        ListOnZoraProposal(globals, zora)
    {}

    receive() external payable {}

    function executeListOnOpensea(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    )
        public
        returns (bytes memory nextProgressData)
    {
        return _executeListOnOpensea(params);
    }
}
