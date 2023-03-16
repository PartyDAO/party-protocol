// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "./ListOnOpenseaAdvancedProposal.sol";

// Implements proposal listing an NFT on OpenSea (Seaport). Inherited by the `ProposalExecutionEngine`.
// This contract will be delegatecall'ed into by `Party` proxy instances.
abstract contract ListOnOpenseaProposal is OpenseaHelpers {
    // ABI-encoded `proposalData` passed into execute.
    struct OpenseaProposalData {
        // The price (in ETH) to sell the NFT.
        uint256 listPrice;
        // How long the listing is valid for.
        uint40 duration;
        // The NFT token contract.
        IERC721 token;
        // the NFT token ID.
        uint256 tokenId;
        // Fees the taker must pay when filling the listing.
        uint256[] fees;
        // Respective recipients for each fee.
        address payable[] feeRecipients;
        // The first 4 bytes of the hash of a domain to attribute the listing to.
        // https://opensea.notion.site/opensea/Proposal-for-Seaport-Order-Attributions-via-Arbitrary-Domain-Hash-d0ad30b994ba48278c6e922983175285
        bytes4 domainHashPrefix;
    }

    // Try to create a listing (ultimately) on OpenSea (Seaport).
    // Creates a listing on Zora auction house for list price first. When that ends,
    // calling this function again will list on OpenSea. When that ends,
    // calling this function again will cancel the listing.
    function _executeListOnOpensea(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) internal returns (bytes memory nextProgressData) {
        OpenseaProposalData memory data = abi.decode(params.proposalData, (OpenseaProposalData));

        return
            _executeAdvancedOpenseaProposal(
                params,
                ListOnOpenseaAdvancedProposal.OpenseaAdvancedProposalData({
                    startPrice: data.listPrice,
                    endPrice: data.listPrice,
                    duration: data.duration,
                    tokenType: ListOnOpenseaAdvancedProposal.TokenType.ERC721,
                    token: address(data.token),
                    tokenId: data.tokenId,
                    fees: data.fees,
                    feeRecipients: data.feeRecipients,
                    domainHashPrefix: data.domainHashPrefix
                })
            );
    }
}
