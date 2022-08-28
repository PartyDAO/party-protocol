// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../party/PreciousList.sol";
import "../tokens/IERC721.sol";
import "../party/PartyGovernance.sol";
import "../utils/LibAddress.sol";

// Implements proposal adding new precious tokens to a party.
contract AddPreciousesProposal is PreciousList {
    using LibAddress for address;

    // ABI-encoded `proposalData` passed into execute.
    struct AddPreciousesProposalData {
        IERC721[] newPreciousTokens;
        uint256[] newPreciousTokenIds;
    }

    error MissingPrecious(IERC721 token, uint256 tokenId);
    error PreciousNotReceived(IERC721 token, uint256 tokenId);

    event UpdatedPreciouses(
        IERC721[] oldPreciousTokens,
        uint256[] oldPreciousTokenIds,
        IERC721[] newPreciousTokens,
        uint256[] newPreciousTokenIds
    );

    function _executeAddPreciouses(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) internal returns (bytes memory nextProgressData) {
        // Decode the proposal data.
        AddPreciousesProposalData memory data = abi.decode(
            params.proposalData,
            (AddPreciousesProposalData)
        );
        // Set the new preciouses. Do this before `_checkNoMissingPreciouses`
        // because it will mutate `newPreciousTokens`.
        _setPreciousList(data.newPreciousTokens, data.newPreciousTokenIds);
        emit UpdatedPreciouses(
            params.preciousTokens,
            params.preciousTokenIds,
            data.newPreciousTokens,
            data.newPreciousTokenIds
        );
        // Check that there are no missing preciouses between the old and new
        // precious lists and null out (ie. set to address(0)) any addresses from
        // the old list.
        _checkNoMissingPreciouses(
            params.preciousTokens,
            params.preciousTokenIds,
            data.newPreciousTokens,
            data.newPreciousTokenIds
        );
        // Check that party owns all added preciouses (should have been
        // transferered to the party before executing proposal).
        _checkReceived(data.newPreciousTokens, data.newPreciousTokenIds);
        // Nothing left to do.
        return "";
    }

    function _checkNoMissingPreciouses(
        IERC721[] memory oldPreciousTokens,
        uint256[] memory oldPreciousTokenIds,
        IERC721[] memory newPreciousTokens,
        uint256[] memory newPreciousTokenIds
    ) internal pure {
        for (uint256 i; i < oldPreciousTokens.length; i++) {
            IERC721 oldPreciousToken = oldPreciousTokens[i];
            uint256 oldPreciousTokenId = oldPreciousTokenIds[i];

            bool found;
            for (uint256 j; j < newPreciousTokens.length; j++) {
                if (
                    oldPreciousToken == newPreciousTokens[j] &&
                    oldPreciousTokenId == newPreciousTokenIds[j]
                ) {
                    found = true;
                    delete newPreciousTokens[j];
                    break;
                }
            }

            if (!found) {
                revert MissingPrecious(oldPreciousToken, oldPreciousTokenId);
            }
        }
    }

    function _checkReceived(
        IERC721[] memory newPreciousTokens,
        uint256[] memory newPreciousTokenIds
    ) internal view {
        for (uint256 i; i < newPreciousTokens.length; i++) {
            IERC721 token = newPreciousTokens[i];
            uint256 tokenId = newPreciousTokenIds[i];

            // Skip if null address.
            if (address(token) == address(0)) continue;

            // Check if we have the precious.
            if (token.ownerOf(tokenId) != address(this)) {
                revert PreciousNotReceived(token, tokenId);
            }
        }
    }
}
