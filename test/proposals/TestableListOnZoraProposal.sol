// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/ListOnOpenseaProposal.sol";
import "../../contracts/proposals/ListOnZoraProposal.sol";
import "../../contracts/tokens/ERC721Receiver.sol";

contract TestableListOnZoraProposal is ListOnZoraProposal, ERC721Receiver {
    constructor(
        IGlobals globals,
        IZoraAuctionHouse zoraAuctionHouse
    ) ListOnZoraProposal(globals, zoraAuctionHouse) {}

    function executeListOnZora(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) public returns (bytes memory nextProgressData) {
        return _executeListOnZora(params);
    }

    receive() external payable {}
}
