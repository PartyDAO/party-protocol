// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/ListOnOpenseaProposal.sol";
import "../../contracts/proposals/ListOnZoraProposal.sol";
import "../../contracts/tokens/ERC721Receiver.sol";

contract TestableListOnZoraProposal is ListOnZoraProposal, ERC721Receiver {
    constructor(
        IGlobals globals,
        IReserveAuctionCoreEth zoraAuctionHouse
    ) ListOnZoraProposal(globals, zoraAuctionHouse) {}

    function executeListOnZora(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) public returns (bytes memory nextProgressData) {
        return _executeListOnZora(params);
    }

    receive() external payable {}
}

contract UnitTestableListOnZoraProposal is TestableListOnZoraProposal {
    constructor(
        IGlobals globals,
        IReserveAuctionCoreEth zoraAuctionHouse
    ) TestableListOnZoraProposal(globals, zoraAuctionHouse) {}

    // Transfer and create a Zora auction for the `token` + `tokenId`.
    function _createZoraAuction(
        // The minimum bid.
        uint256 listPrice,
        // How long the auction must wait for the first bid.
        uint40 timeout,
        // How long the auction will run for once a bid has been placed.
        uint40 duration,
        address token,
        uint256 tokenId
    ) internal override {
        ZORA.createAuction(token, tokenId, duration, listPrice, address(this), 0);
        emit ZoraAuctionCreated(
            token,
            tokenId,
            listPrice,
            duration,
            uint40(block.timestamp + timeout)
        );
    }
}
