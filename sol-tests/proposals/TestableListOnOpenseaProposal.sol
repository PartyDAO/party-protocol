// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/ListOnOpenseaProposal.sol";
import "../../contracts/proposals/ListOnOpenseaAdvancedProposal.sol";
import "../../contracts/proposals/ListOnZoraProposal.sol";
import "../../contracts/tokens/ERC721Receiver.sol";
import "../../contracts/tokens/ERC1155Receiver.sol";

contract TestableListOnOpenseaProposal is
    ListOnOpenseaProposal,
    ListOnOpenseaAdvancedProposal,
    ListOnZoraProposal,
    ERC721Receiver,
    ERC1155Receiver
{
    constructor(
        IGlobals globals,
        IOpenseaExchange seaport,
        IOpenseaConduitController conduitController,
        IZoraAuctionHouse zora
    )
        ListOnOpenseaAdvancedProposal(globals, seaport, conduitController)
        ListOnZoraProposal(globals, zora)
    {}

    receive() external payable {}

    function executeListOnOpensea(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) public returns (bytes memory nextProgressData) {
        return _executeListOnOpensea(params);
    }

    function executeListOnOpenseaAdvanced(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) public returns (bytes memory nextProgressData) {
        return _executeListOnOpenseaAdvanced(params);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public pure override(ERC721Receiver, ERC1155Receiver) returns (bool) {
        return
            ERC721Receiver.supportsInterface(interfaceId) ||
            ERC1155Receiver.supportsInterface(interfaceId);
    }
}
